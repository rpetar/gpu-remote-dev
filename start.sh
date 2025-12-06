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
# Required environment variables
# ------------------------------------------------------------
TUNNEL_NAME="${TUNNEL_NAME:-gpu-workspace}"

[ -z "$TUNNEL_ID" ] && error "TUNNEL_ID must be set"
[ -z "$ACCESS_TOKEN" ] && error "ACCESS_TOKEN must be set"

# ------------------------------------------------------------
# GPU Detection
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Clone GitHub Repository
# ------------------------------------------------------------
echo ""
/clone_repo.sh

# ------------------------------------------------------------
# Start VS Code Tunnel
# ------------------------------------------------------------
echo ""
echo "🔗 Starting VS Code Tunnel..."

info "Tunnel ID: $TUNNEL_ID"

# Start VS Code tunnel with existing tunnel credentials
code tunnel --accept-server-license-terms \
    --name "$TUNNEL_NAME" \
    --tunnel-id "$TUNNEL_ID" \
    --host-token "$ACCESS_TOKEN" \
    > /tmp/vscode_tunnel.log 2>&1 &
TUNNEL_PID=$!

sleep 5

if ! ps -p "$TUNNEL_PID" >/dev/null; then
    error "VS Code Tunnel failed to start! Log:"
    cat /tmp/vscode_tunnel.log
fi

info "VS Code Tunnel started (PID: $TUNNEL_PID)"
info "Connect via VS Code Remote Explorer -> Tunnels -> $TUNNEL_ID"

# ------------------------------------------------------------
# Ready banner
# ------------------------------------------------------------
echo ""
banner "Container Ready!"

echo "GPU: ${GPU_NAME:-N/A}"
echo "Storage: /workspace"
echo "VS Code Tunnel: $TUNNEL_ID"
echo "Logs: /tmp/vscode_tunnel.log"

# ------------------------------------------------------------
# Graceful shutdown
# ------------------------------------------------------------
trap '
    echo "Shutting down..."
    kill "$TUNNEL_PID" 2>/dev/null || true
    exit 0
' EXIT TERM INT

# ------------------------------------------------------------
# Monitor tunnel process
# ------------------------------------------------------------
while true; do
    if ! ps -p "$TUNNEL_PID" > /dev/null; then
        echo ""
        error "VS Code Tunnel process died! Last 50 log lines:"
        tail -n 50 /tmp/vscode_tunnel.log
    fi
    sleep 5
done