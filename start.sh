#!/bin/bash
set -e

banner() {
    echo "================================================="
    echo "$1"
    echo "================================================="
}

error() {
    echo "❌ ERROR: $1"
    exit 1
}

warn() {
    echo "⚠ $1"
}

info() {
    echo "✓ $1"
}

banner "GPU Development Container Initialization"

# ------------------------------------------------------------
# Mode selection and defaults
# ------------------------------------------------------------
CONNECT_MODE="${CONNECT_MODE:-auto}"  # ssh | tunnel | auto
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-2222}"
TUNNEL_NAME="${TUNNEL_NAME:-gpu-workspace}"
PUBLIC_KEY_RESOLVED="${PUBLIC_KEY:-${SSH_PUBLIC_KEY:-${PUBLIC_SSH_KEY:-}}}"

PROC_PID=""
PROC_NAME=""
PROC_LOG=""

# ------------------------------------------------------------
# GPU Detection
# ------------------------------------------------------------

detect_gpu() {
    echo ""
    echo "🔍 Detecting GPU..."

    if command -v nvidia-smi &> /dev/null; then
        info "NVIDIA drivers detected"
        nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
        echo ""
        echo "GPU Details:"
        nvidia-smi -L

        nvidia-smi -pm 1 2>/dev/null || warn "Could not enable persistence mode"

        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
        GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)

        info "GPU: $GPU_NAME with ${GPU_MEMORY}MB memory"
    else
        warn "nvidia-smi not found - GPU may not be available"
        echo "Make sure:"
        echo "  1. Host has NVIDIA GPU & drivers"
        echo "  2. Docker started with --gpus all"
        echo "  3. NVIDIA Container Toolkit is installed"
    fi

    mkdir -p /tmp/cuda_cache
}

# ------------------------------------------------------------
# VS Code Tunnel flow
# ------------------------------------------------------------

start_vscode_tunnel() {
    [ -z "$TUNNEL_ID" ] && error "TUNNEL_ID must be set"
    [ -z "$ACCESS_TOKEN" ] && error "ACCESS_TOKEN must be set"

    echo ""
    echo "🔗 Starting VS Code Tunnel..."
    info "Tunnel ID: $TUNNEL_ID"

    code tunnel --accept-server-license-terms \
        --name "$TUNNEL_NAME" \
        --tunnel-id "$TUNNEL_ID" \
        --host-token "$ACCESS_TOKEN" \
        > /tmp/vscode_tunnel.log 2>&1 &
    TUNNEL_PID=$!

    sleep 5

    if ! ps -p "$TUNNEL_PID" >/dev/null; then
        echo ""
        echo "VS Code Tunnel failed to start! Log:"
        cat /tmp/vscode_tunnel.log
        error "VS Code Tunnel failed to start"
    fi

    code tunnel status --tunnel-id "$TUNNEL_ID" > /tmp/vscode_tunnel.status 2>&1 || true
    if ! grep -q "State: Connected" /tmp/vscode_tunnel.status; then
        echo ""
        echo "VS Code Tunnel status:"
        cat /tmp/vscode_tunnel.status
        echo ""
        echo "Log tail:" && tail -n 50 /tmp/vscode_tunnel.log || true
        error "VS Code Tunnel failed to connect"
    fi

    info "VS Code Tunnel started (PID: $TUNNEL_PID)"
    info "Connect via VS Code Remote Explorer -> Tunnels -> $TUNNEL_ID"

    PROC_PID="$TUNNEL_PID"
    PROC_NAME="VS Code Tunnel"
    PROC_LOG="/tmp/vscode_tunnel.log"
}

# ------------------------------------------------------------
# SSH flow
# ------------------------------------------------------------

start_sshd() {
    [ -z "$PUBLIC_KEY_RESOLVED" ] && error "PUBLIC_KEY (or SSH_PUBLIC_KEY) must be set (your public key line)"

    echo ""
    echo "🔐 Configuring SSH server..."

    if ! command -v sshd >/dev/null; then
        info "Installing openssh-server..."
        apt-get update && apt-get install -y openssh-server && rm -rf /var/lib/apt/lists/*
    fi

    if ! id "$SSH_USER" >/dev/null 2>&1; then
        info "Creating user $SSH_USER"
        useradd -m -s /bin/bash "$SSH_USER"
    fi

    USER_HOME=$(getent passwd "$SSH_USER" | cut -d: -f6)
    [ -z "$USER_HOME" ] && error "Unable to determine home for $SSH_USER"

    mkdir -p "$USER_HOME/.ssh"
    chmod 700 "$USER_HOME/.ssh"
    printf '%s\n' "$PUBLIC_KEY_RESOLVED" > "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    chown -R "$SSH_USER":"$SSH_USER" "$USER_HOME/.ssh"

    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/zzz_container.conf <<EOF_CONF
Port $SSH_PORT
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
ChallengeResponseAuthentication no
UsePAM yes
EOF_CONF

    mkdir -p /var/run/sshd

    /usr/sbin/sshd -D -e -p "$SSH_PORT" > /tmp/sshd.log 2>&1 &
    SSHD_PID=$!

    sleep 2

    if ! ps -p "$SSHD_PID" >/dev/null; then
        echo ""
        echo "sshd failed to start! Log:"
        tail -n 50 /tmp/sshd.log
        error "sshd failed to start"
    fi

    info "sshd started (PID: $SSHD_PID) on port $SSH_PORT for user $SSH_USER"
    info "Connect via: ssh -p $SSH_PORT $SSH_USER@<host>"

    PROC_PID="$SSHD_PID"
    PROC_NAME="sshd"
    PROC_LOG="/tmp/sshd.log"
}

# ------------------------------------------------------------
# Mode selection
# ------------------------------------------------------------

resolve_mode() {
    case "$CONNECT_MODE" in
        ssh)
            echo "ssh"
            ;;
        tunnel)
            echo "tunnel"
            ;;
        auto)
            if [ -n "$PUBLIC_KEY_RESOLVED" ]; then
                echo "ssh"
            else
                echo "tunnel"
            fi
            ;;
        *)
            error "CONNECT_MODE must be one of: ssh, tunnel, auto"
            ;;
    esac
}

MODE=$(resolve_mode)
info "Connection mode: $MODE"

detect_gpu

if [ "$MODE" = "ssh" ]; then
    start_sshd
else
    start_vscode_tunnel
fi

# ------------------------------------------------------------
# Prepare the workspace
# ------------------------------------------------------------

echo ""
/workspace_bootstrap.sh

# ------------------------------------------------------------
# Ready banner
# ------------------------------------------------------------

echo ""
banner "Container Ready!"

echo "GPU: ${GPU_NAME:-N/A}"
echo "Storage: /workspace"
if [ "$MODE" = "ssh" ]; then
    echo "SSH: $SSH_USER on port $SSH_PORT (key from PUBLIC_KEY/SSH_PUBLIC_KEY)"
else
    echo "VS Code Tunnel: $TUNNEL_ID"
fi
echo "Logs: $PROC_LOG"

# ------------------------------------------------------------
# Graceful shutdown
# ------------------------------------------------------------
trap '
    echo "Shutting down..."
    kill "$PROC_PID" 2>/dev/null || true
    exit 0
' EXIT TERM INT

# ------------------------------------------------------------
# Monitor main connection process
# ------------------------------------------------------------
while true; do
    if ! ps -p "$PROC_PID" > /dev/null; then
        echo ""
        echo "$PROC_NAME process died! Last 50 log lines:"
        tail -n 50 "$PROC_LOG"
        error "$PROC_NAME process died"
    fi
    sleep 5
done
