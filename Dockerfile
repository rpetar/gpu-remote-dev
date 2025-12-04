FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install required packages including GPU monitoring tools
RUN apt-get update && apt-get install -y \
    fuse \
    wget \
    curl \
    unzip \
    ca-certificates \
    git \
    build-essential \
    nano \
    gpg \
    pciutils \
    lshw \
    htop \
    nvtop \
    python3 \
    python3-pip \
    lsb-release \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Azure CLI
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install BlobFuse2
RUN wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb && \
    dpkg -i packages-microsoft-prod.deb && \
    rm packages-microsoft-prod.deb && \
    apt-get update && \
    apt-get install -y blobfuse2 && \
    rm -rf /var/lib/apt/lists/*

# Install VS Code CLI
RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz && \
    tar -xf vscode_cli.tar.gz -C /usr/local/bin && \
    rm vscode_cli.tar.gz && \
    chmod +x /usr/local/bin/code

# Install GPU monitoring and ML libraries
RUN pip3 install --no-cache-dir \
    gpustat \
    nvidia-ml-py3 \
    psutil

# Create mount and config dirs with proper permissions
RUN mkdir -p /mnt/workspace \
    && mkdir -p /etc/blobfuse2 \
    && mkdir -p /tmp/blobfuse2_cache \
    && chmod 755 /mnt/workspace /tmp/blobfuse2_cache

# Copy configuration and scripts
COPY blobfuse2_config.yaml /etc/blobfuse2/config.yaml
COPY start.sh /start.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /start.sh /healthcheck.sh

# Set working directory
WORKDIR /mnt/workspace

# Health check for container monitoring
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/healthcheck.sh"]

# Environment variables for GPU
ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_CACHE_PATH=/tmp/cuda_cache

ENTRYPOINT ["/start.sh"]
