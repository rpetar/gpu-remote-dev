FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y \
    fuse \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Azure DevTunnel CLI
RUN curl -sL https://aka.ms/DevTunnelCliInstall | sed 's/sudo //g' | bash \
    && DEV_BIN=$(find /root/bin /usr -type f -name devtunnel 2>/dev/null | head -n 1) \
    && DEV_DIR=$(dirname "$DEV_BIN") \
    && echo "export PATH=\"$DEV_DIR:\$PATH\"" >> /root/.bashrc \
    && echo "export PATH=\"$DEV_DIR:\$PATH\"" >> /etc/profile

RUN devtunnel --version

# BlobFuse2
RUN curl -LO https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y blobfuse2 \
    && rm -rf /var/lib/apt/lists/*

# GPU monitoring
RUN pip3 install --no-cache-dir gpustat nvidia-ml-py3 psutil

RUN mkdir -p /mnt/workspace /etc/blobfuse2 /tmp/blobfuse2_cache \
    && chmod 755 /mnt/workspace /tmp/blobfuse2_cache

COPY blobfuse2_config.yaml /etc/blobfuse2/config.yaml
COPY start.sh /start.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /start.sh /healthcheck.sh

WORKDIR /mnt/workspace

HEALTHCHECK --interval=30s --timeout=10s \
    CMD ["/healthcheck.sh"]

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_CACHE_PATH=/tmp/cuda_cache

ENTRYPOINT ["/bin/bash", "-lc", "/start.sh"]