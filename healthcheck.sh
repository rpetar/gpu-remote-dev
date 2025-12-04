#!/bin/bash

# Health check script for container monitoring
# This checks if critical services are running properly

EXIT_CODE=0

# Check if VS Code tunnel process is running
if ! pgrep -f "code tunnel" > /dev/null; then
    echo "UNHEALTHY: VS Code tunnel is not running"
    EXIT_CODE=1
fi

# Check if blobfuse2 mount is active
if ! mountpoint -q /mnt/workspace; then
    echo "UNHEALTHY: Azure Blob Storage is not mounted"
    EXIT_CODE=1
fi

# Check GPU availability (if expected)
if command -v nvidia-smi &> /dev/null; then
    if ! nvidia-smi > /dev/null 2>&1; then
        echo "UNHEALTHY: GPU not accessible"
        EXIT_CODE=1
    fi
fi

# Check disk space for cache
CACHE_USAGE=$(df /tmp/blobfuse2_cache | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$CACHE_USAGE" -gt 90 ]; then
    echo "WARNING: Cache disk usage at ${CACHE_USAGE}%"
fi

if [ $EXIT_CODE -eq 0 ]; then
    echo "HEALTHY: All services operational"
fi

exit $EXIT_CODE
