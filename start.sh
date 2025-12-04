#!/bin/bash
set -e

echo "================================================="
echo "GPU Development Container Initialization"
echo "================================================="

# Set default for CONTAINER_NAME if not provided
if [ -z "$CONTAINER_NAME" ]; then
    export CONTAINER_NAME="workspace"
fi

# Validate required environment variables
if [ -z "$ACCOUNT_NAME" ] || [ -z "$ACCOUNT_KEY" ]; then
    echo "❌ ERROR: ACCOUNT_NAME and ACCOUNT_KEY must be set"
    exit 1
fi

if [ -z "$TUNNEL_ID" ] || [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ ERROR: TUNNEL_ID and ACCESS_TOKEN must be set"
    exit 1
fi

# GPU Detection and Information
echo ""
echo "🔍 Detecting GPU..."
if command -v nvidia-smi &> /dev/null; then
    echo "✓ NVIDIA drivers detected"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
    echo ""
    echo "GPU Details:"
    nvidia-smi -L

    # Set GPU performance mode if available 
    nvidia-smi -pm 1 2>/dev/null || echo "⚠ Could not set persistence mode (may require root)"

    # Export GPU info for later use
    export GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1)
    export GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
    echo "✓ GPU: $GPU_NAME with ${GPU_MEMORY}MB memory"
else
    echo "⚠ Warning: nvidia-smi not found - GPU may not be available"
    echo "This container expects GPU access. Please ensure:"
    echo "  1. Host has NVIDIA GPU and drivers installed"
    echo "  2. Container runtime is configured for GPU access (--gpus all)"
    echo "  3. nvidia-docker runtime is properly configured"
fi

# Create CUDA cache directory
mkdir -p /tmp/cuda_cache

echo ""
echo "💾 Mounting Azure Blob Storage..."

# DEBUG: Check if config file exists and show its contents
echo "DEBUG: Checking config file..."
if [ -f /etc/blobfuse2/config.yaml ]; then
    echo "DEBUG: Config file found at /etc/blobfuse2/config.yaml"
    echo "DEBUG: Config file contents:"
    cat /etc/blobfuse2/config.yaml
    echo ""
else
    echo "❌ DEBUG ERROR: Config file NOT found at /etc/blobfuse2/config.yaml"
    ls -la /etc/blobfuse2/ || echo "DEBUG: /etc/blobfuse2/ directory doesn't exist"
fi

# DEBUG: Check environment variables
echo "DEBUG: Environment variables check:"
echo "  ACCOUNT_NAME=${ACCOUNT_NAME:-NOT SET}"
echo "  ACCOUNT_KEY=${ACCOUNT_KEY:0:10}... (truncated)"
echo "  CONTAINER_NAME=${CONTAINER_NAME:-NOT SET}"
echo ""

# DEBUG: Run blobfuse2 with verbose output
echo "DEBUG: Attempting BlobFuse2 mount with verbose output..."
if blobfuse2 mount /mnt/workspace --config-file=/etc/blobfuse2/config.yaml -o allow_other 2>&1 | tee /tmp/blobfuse2_debug.log; then
    echo "✓ Azure Blob Storage mounted successfully"
else
    echo "⚠ Warning: Failed to mount Azure Blob Storage, but continuing..."
    echo "DEBUG: Full BlobFuse2 output saved to /tmp/blobfuse2_debug.log"
    echo "DEBUG: Last 20 lines of debug log:"
    tail -n 20 /tmp/blobfuse2_debug.log || true
fi

# Verify mount
if mountpoint -q /mnt/workspace; then
    echo "✓ Mount point verified: /mnt/workspace"
    ls -la /mnt/workspace | head -n 10
else
    echo "⚠ Warning: /mnt/workspace is not a mount point"
fi

echo ""
echo "🔗 Starting VS Code Tunnel..."
code tunnel --accept-server-license-terms \
    --name "$TUNNEL_ID" \
    --access-token "$ACCESS_TOKEN" \
    > /tmp/vscode_tunnel.log 2>&1 &

TUNNEL_PID=$!

if ps -p $TUNNEL_PID > /dev/null; then
    echo "✓ VS Code Tunnel started (PID: $TUNNEL_PID)"
    echo "✓ Connect via: https://vscode.dev/tunnel/$TUNNEL_ID"
else
    echo "❌ ERROR: Failed to start VS Code Tunnel"
    cat /tmp/vscode_tunnel.log
    exit 1
fi

# Start GPU monitoring in background
if command -v gpustat &> /dev/null; then
    echo ""
    echo "📊 Starting GPU monitoring..."
    while true; do
        gpustat --json > /tmp/gpu_stats.json 2>/dev/null || true
        sleep 10
    done &
    MONITOR_PID=$!
    echo "✓ GPU monitoring started (PID: $MONITOR_PID)"
fi

echo ""
echo "================================================="
echo "✅ Container Ready!"
echo "================================================="
echo "GPU: $GPU_NAME"
echo "Storage: /mnt/workspace"
echo "VS Code Tunnel: $TUNNEL_ID"
echo "Logs: /tmp/vscode_tunnel.log"
echo "GPU Stats: /tmp/gpu_stats.json"
echo "================================================="

# Keep container alive and handle signals gracefully
trap "echo 'Shutting down...'; kill $TUNNEL_PID 2>/dev/null; [ ! -z \$MONITOR_PID ] && kill \$MONITOR_PID 2>/dev/null; exit 0" EXIT TERM INT

# Wait for tunnel process
wait $TUNNEL_PID
