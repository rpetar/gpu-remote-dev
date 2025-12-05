FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Use bash for RUN commands
SHELL ["/bin/bash", "-lc"]

# ---------------------------------------------------------
# Base packages
# ---------------------------------------------------------
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

# ---------------------------------------------------------
# GitHub CLI
# ---------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# Azure DevTunnel CLI (auto-detect install path)
# ---------------------------------------------------------
RUN curl -sL https://aka.ms/DevTunnelCliInstall | sed 's/sudo //g' | bash

# Detect where devtunnel binary was installed and add to PATH
RUN DEV_BIN=$(find /root/bin /usr -type f -name devtunnel 2>/dev/null | head -n 1) \
    && DEV_DIR=$(dirname "$DEV_BIN") \
    && echo "DevTunnel installed at: $DEV_BIN" \
    && echo "export PATH=\"$DEV_DIR:\$PATH\"" >> /etc/profile \
    && echo "export PATH=\"$DEV_DIR:\$PATH\"" >> /root/.bashrc \
    && export PATH="$DEV_DIR:$PATH"

# Verify install works inside Docker build
RUN devtunnel --version

# ---------------------------------------------------------
# Azure CLI
# ---------------------------------------------------------
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# ---------------------------------------------------------
# BlobFuse2
# ---------------------------------------------------------
RUN wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb \
    && dpkg -i packages-microsoft-prod.deb \
    && rm packages-microsoft-prod.deb \
    && apt-get update \
    && apt-get install -y blobfuse2 \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------
# VS Code CLI
# ---------------------------------------------------------
RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
    --output vscode_cli.tar.gz \
    && tar -xf vscode_cli.tar.gz -C /usr/local/bin \
    && rm vscode_cli.tar.gz \
    && chmod +x /usr/local/bin/code

# ---------------------------------------------------------
# Python GPU Monitoring Tools
# ---------------------------------------------------------
RUN pip3 install --no-cache-dir \
    gpustat \
    nvidia-ml-py3 \
    psutil

# ---------------------------------------------------------
# Directories & permissions
# ---------------------------------------------------------
RUN mkdir -p /mnt/workspace \
    && mkdir -p /etc/blobfuse2 \
    && mkdir -p /tmp/blobfuse2_cache \
    && chmod 755 /mnt/workspace /tmp/blobfuse2_cache

# ---------------------------------------------------------
# Copy scripts & config
# ---------------------------------------------------------
COPY blobfuse2_config.yaml /etc/blobfuse2/config.yaml
COPY start.sh /start.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /start.sh /healthcheck.sh

# ---------------------------------------------------------
# Runtime Environment
# ---------------------------------------------------------
WORKDIR /mnt/workspace

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/healthcheck.sh"]

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_CACHE_PATH=/tmp/cuda_cache

ENTRYPOINT ["/bin/bash", "-lc", "/start.sh"]