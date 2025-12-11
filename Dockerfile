FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-lc"]

RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    wget \
    git \
    ffmpeg \
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    jq \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

# Python package manager (uv)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# GPU monitoring
RUN pip3 install --no-cache-dir gpustat nvidia-ml-py3 psutil

# VS Code Server CLI
RUN curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' \
    --output /tmp/vscode_cli.tar.gz \
    && tar -xf /tmp/vscode_cli.tar.gz -C /usr/local/bin \
    && rm /tmp/vscode_cli.tar.gz \
    && chmod +x /usr/local/bin/code

RUN mkdir -p /workspace && chmod 755 /workspace

COPY start.sh /start.sh
COPY workspace_bootstrap.sh /workspace_bootstrap.sh
COPY healthcheck.sh /healthcheck.sh
RUN chmod +x /start.sh /workspace_bootstrap.sh /healthcheck.sh

WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=10s \
    CMD ["/healthcheck.sh"]

ENV NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    CUDA_CACHE_PATH=/tmp/cuda_cache

ENTRYPOINT ["/bin/bash", "-lc", "/start.sh"]