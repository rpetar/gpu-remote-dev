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
    echo "GPU Details:"d
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

# Check if FUSE is available
if [ ! -e /dev/fuse ]; then
    echo "⚠ Warning: FUSE device not available - BlobFuse2 mounting not supported"
    echo "   This is expected on restricted container platforms like Salad"
    echo "   Use Azure SDK in your code to access blob storage instead"
    echo "   Credentials available via environment variables:"
    echo "     ACCOUNT_NAME=$ACCOUNT_NAME"
    echo "     ACCOUNT_KEY=<set>"
    echo "     CONTAINER_NAME=$CONTAINER_NAME"
    mkdir -p /mnt/workspace
    MOUNT_AVAILABLE=false
else
    # Generate config file with actual values (BlobFuse2 doesn't expand env vars in YAML)
    echo "DEBUG: Generating runtime config file with actual values..."
    sed -e "s|\${ACCOUNT_NAME}|${ACCOUNT_NAME}|g" \
        -e "s|\${ACCOUNT_KEY}|${ACCOUNT_KEY}|g" \
        -e "s|\${CONTAINER_NAME}|${CONTAINER_NAME}|g" \
        /etc/blobfuse2/config.yaml > /tmp/blobfuse2_runtime.yaml

    # Attempt BlobFuse2 mount
    blobfuse2 mount /mnt/workspace --config-file=/tmp/blobfuse2_runtime.yaml -o allow_other 2>&1 | tee /tmp/blobfuse2_debug.log
    BLOBFUSE_EXIT_CODE=${PIPESTATUS[0]}

    if [ $BLOBFUSE_EXIT_CODE -eq 0 ]; then
        echo "✓ Azure Blob Storage mounted successfully"
        MOUNT_AVAILABLE=true
    else
        echo "⚠ Warning: Failed to mount Azure Blob Storage (exit code: $BLOBFUSE_EXIT_CODE)"
        echo "   Use Azure SDK in your code to access blob storage instead"
        MOUNT_AVAILABLE=false
    fi
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

# Give it a moment to start
sleep 2

if ps -p $TUNNEL_PID > /dev/null; then
    echo "✓ VS Code Tunnel started (PID: $TUNNEL_PID)"
    echo "✓ Connect via: https://vscode.dev/tunnel/$TUNNEL_ID"
else
    echo "❌ ERROR: VS Code Tunnel failed to start"
    echo "Check the log for details:"
    cat /tmp/vscode_tunnel.log
    echo ""
    echo "Common issues:"
    echo "  - Invalid ACCESS_TOKEN"
    echo "  - TUNNEL_ID already in use"
    echo "  - Network connectivity problems"
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

# Monitor tunnel process and show logs if it dies
while true; do
    if ! ps -p $TUNNEL_PID > /dev/null; then
        echo ""
        echo "❌ VS Code Tunnel process died!"
        echo "Last 50 lines of tunnel log:"
        tail -n 50 /tmp/vscode_tunnel.log
        exit 1
    fi
    sleep 5
done
