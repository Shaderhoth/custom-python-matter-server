FROM python:3.12-slim-bookworm

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /app

# Install build and runtime dependencies
RUN \
    set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        git \
        build-essential \
        libuv1-dev \
        zlib1g-dev \
        libjson-c-dev \
        libnl-3-dev \
        libnl-route-3-dev \
        libnl-genl-3-dev \
        unzip \
        gdb \
        iputils-ping \
        iproute2 \
        python3-dev \
        ninja-build \
        clang \
        libffi-dev \
        cmake \
        pkg-config \
        libssl-dev \
    && rm -rf \
        /var/lib/apt/lists/* \
        /usr/src/*

# Install Rust using rustup
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN \
    curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal \
    && rustup default stable

ARG PYTHON_MATTER_SERVER

ENV chip_example_url="https://github.com/home-assistant-libs/matter-linux-ota-provider/releases/download/2024.7.2"
ARG TARGETPLATFORM

RUN \
    set -x \
    && echo "${TARGETPLATFORM}" \
    && if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then \
        curl -Lo /usr/local/bin/chip-ota-provider-app "${chip_example_url}/chip-ota-provider-app-x86-64"; \
    elif [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        curl -Lo /usr/local/bin/chip-ota-provider-app "${chip_example_url}/chip-ota-provider-app-aarch64"; \
    else \
        exit 1; \
    fi \
    && chmod +x /usr/local/bin/chip-ota-provider-app

# Upgrade pip to the latest version
RUN pip install --upgrade pip

# Install the custom Python Matter server from source
RUN \
    pip3 install --no-cache-dir --no-binary :all: "custom-python-matter-server[server]==${PYTHON_MATTER_SERVER}"

VOLUME ["/data"]
EXPOSE 5580

ENTRYPOINT [ "matter-server" ]
CMD [ "--storage-path", "/data", "--paa-root-cert-dir", "/data/credentials" ]
