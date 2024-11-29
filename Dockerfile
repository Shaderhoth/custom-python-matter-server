# Stage 1: Use Alpine with pre-built glibc
FROM frolvlad/alpine-glibc:latest AS glibc

# Install additional dependencies (if required)
RUN apk add --no-cache \
    bash \
    curl \
    libuv \
    zlib \
    json-c

# Stage 2: Use the Python 3.12-slim base image
FROM python:3.12-slim-bookworm

# Set the shell for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set working directory
WORKDIR /app

# Copy glibc from the Alpine stage
COPY --from=glibc /usr/glibc-compat /usr/glibc-compat

# Add glibc to the library path
ENV LD_LIBRARY_PATH="/usr/glibc-compat/lib:$LD_LIBRARY_PATH"

# Install essential build tools and runtime dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    curl \
    libuv1 \
    zlib1g \
    libjson-c5 \
    libnl-3-200 \
    libnl-route-3-200 \
    unzip \
    gdb \
    iputils-ping \
    iproute2 && \
    rm -rf /var/lib/apt/lists/*

# Set build arguments and environment variables
ARG PYTHON_MATTER_SERVER
ARG TARGETPLATFORM
ENV chip_example_url="https://github.com/home-assistant-libs/matter-linux-ota-provider/releases/download/2024.7.2"

# Download and install the Matter OTA provider app
RUN set -x && \
    if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then \
        curl -Lo /usr/local/bin/chip-ota-provider-app "${chip_example_url}/chip-ota-provider-app-x86-64"; \
    elif [ "${TARGETPLATFORM}" = "linux/arm64" ]; then \
        curl -Lo /usr/local/bin/chip-ota-provider-app "${chip_example_url}/chip-ota-provider-app-aarch64"; \
    else \
        echo "Unsupported platform: ${TARGETPLATFORM}" && exit 1; \
    fi && \
    chmod +x /usr/local/bin/chip-ota-provider-app

# Install the custom Python Matter server
RUN pip3 install --no-cache-dir "custom-python-matter-server[server]==${PYTHON_MATTER_SERVER}"

# Define volumes and expose ports
VOLUME ["/data"]
EXPOSE 5580

# Set the entry point and default command
ENTRYPOINT ["matter-server"]
CMD ["--storage-path", "/data", "--paa-root-cert-dir", "/data/credentials"]
