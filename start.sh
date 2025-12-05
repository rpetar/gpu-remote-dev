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
CONTAINER_NAME="${CONTAINER_NAME:-workspace}"

[ -z "$TUNNEL_ID" ]      && error "TUNNEL_ID must be set"
[ -z "$ACCESS_TOKEN" ]   && error "ACCESS_TOKEN must be set"

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
# Mount Azure Blob Storage (BlobFuse2)
# ------------------------------------------------------------
echo ""
echo "💾 Mounting Azure Blob Storage..."

if [ ! -e /dev/fuse ]; then
    warn "FUSE not available - BlobFuse2 disabled"
    echo "Using Azure SDK instead (credentials still provided)"
    mkdir -p /mnt/workspace
    MOUNT_AVAILABLE=false
else
    [ -z "$ACCOUNT_NAME" ] && error "ACCOUNT_NAME must be set when FUSE is available"
    [ -z "$ACCOUNT_KEY" ]  && error "ACCOUNT_KEY must be set when FUSE is available"

    echo "Generating BlobFuse2 config..."
    sed \
        -e "s|\${ACCOUNT_NAME}|${ACCOUNT_NAME}|g" \
        -e "s|\${ACCOUNT_KEY}|${ACCOUNT_KEY}|g" \
        -e "s|\${CONTAINER_NAME}|${CONTAINER_NAME}|g" \
        /etc/blobfuse2/config.yaml \
        > /tmp/blobfuse2_runtime.yaml

    echo "Mounting BlobFuse2..."
    if blobfuse2 mount /mnt/workspace \
        --config-file=/tmp/blobfuse2_runtime.yaml -o allow_other \
        2>&1 | tee /tmp/blobfuse2_debug.log; then
        
        info "Blob Storage mounted"
        MOUNT_AVAILABLE=true
    else
        warn "BlobFuse2 mount failed"
        MOUNT_AVAILABLE=false
    fi
fi

if mountpoint -q /mnt/workspace; then
    info "Mount point OK: /mnt/workspace"
    ls -la /mnt/workspace | head -n 10
else
    warn "/mnt/workspace is not a mount point"
fi

# ------------------------------------------------------------
# Start Dev Tunnel
# ------------------------------------------------------------
echo ""
echo "🔗 Starting Dev Tunnel..."

# Verify devtunnel is available and correct version
if ! command -v devtunnel &> /dev/null; then
    error "devtunnel command not found in PATH"
fi

echo "DevTunnel location: $(which devtunnel)"
devtunnel --version || error "Failed to get devtunnel version"

# Verify --access-token is supported
if ! devtunnel host --help | grep -q "access-token"; then
    error "This devtunnel version doesn't support --access-token. Please update devtunnel."
fi

echo "Using tunnel ID: $TUNNEL_ID"

# Ensure port 8000 exists (idempotent)
devtunnel port create "$TUNNEL_ID" \
    -p 8000 \
    --protocol https \
    --access-token "$ACCESS_TOKEN" \
    | tee /tmp/devtunnel_port.log || true

# Host tunnel
devtunnel host "$TUNNEL_ID" \
    --access-token "$ACCESS_TOKEN" \
    > /tmp/devtunnel.log 2>&1 &
TUNNEL_PID=$!

# Wait for startup
sleep 3

if ! ps -p "$TUNNEL_PID" >/dev/null; then
    error "DevTunnel failed to start! Log:"
    cat /tmp/devtunnel.log
fi

info "Dev Tunnel started (PID: $TUNNEL_PID)"

# Optional: try to show full details, but do NOT fail if unauthorized
TUNNEL_URL=$(devtunnel show "$TUNNEL_ID" --json 2>/dev/null \
    | grep -o '"uri":"[^"]*' | cut -d'"' -f4 || true)

[ -n "$TUNNEL_URL" ] && info "Connect via: $TUNNEL_URL"

# ------------------------------------------------------------
# Ready banner
# ------------------------------------------------------------
echo ""
banner "Container Ready!"

echo "GPU: ${GPU_NAME:-N/A}"
echo "Storage: /mnt/workspace"
echo "Dev Tunnel: $TUNNEL_ID"
echo "Logs: /tmp/devtunnel.log"
echo "GPU Stats: /tmp/gpu_stats.json"

# ------------------------------------------------------------
# Graceful shutdown
# ------------------------------------------------------------
trap '
    echo "Shutting down..."
    kill "$TUNNEL_PID" 2>/dev/null || true
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null || true
    exit 0
' EXIT TERM INT

# ------------------------------------------------------------
# Monitor tunnel process
# ------------------------------------------------------------
while true; do
    if ! ps -p "$TUNNEL_PID" > /dev/null; then
        echo ""
        error "Dev Tunnel process died! Last 50 log lines:"
        tail -n 50 /tmp/devtunnel.log
    fi
    sleep 5
done