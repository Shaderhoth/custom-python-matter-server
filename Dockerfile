# Stage 1: Use Alpine with pre-built glibc
# Stage 1: Use sgerrand's Alpine glibc
FROM alpine:3.18 AS glibc

# Add glibc binaries
RUN apk --no-cache add wget bash && \
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
    wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/2.38-r0/glibc-2.38-r0.apk && \
    apk add --no-cache glibc-2.38-r0.apk && \
    rm -f glibc-2.38-r0.apk

# Stage 2: Use the Python 3.12-slim base image
FROM python:3.12-slim-bookworm

# Copy glibc from the Alpine stage
COPY --from=glibc /usr/glibc-compat /usr/glibc-compat

# Add glibc to the library path
ENV LD_LIBRARY_PATH="/usr/glibc-compat/lib:$LD_LIBRARY_PATH"

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
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
