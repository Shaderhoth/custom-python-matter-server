# Stage 1: Compile glibc from source for ARM64
FROM debian:bookworm AS glibc-builder

# Install dependencies for building glibc
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    gawk \
    bison \
    libc6-dev \
    manpages-dev

# Download and build glibc
RUN wget http://ftp.gnu.org/gnu/libc/glibc-2.35.tar.gz && \
    tar -xzf glibc-2.35.tar.gz && \
    cd glibc-2.35 && \
    mkdir build && cd build && \
    ../configure --prefix=/opt/glibc && \
    make -j$(nproc) && \
    make install

# Stage 2: Use the Python 3.12-slim base image
FROM python:3.12-slim-bookworm

# Copy glibc from the build stage
COPY --from=glibc-builder /opt/glibc /opt/glibc

# Add the compiled glibc to the runtime path
ENV LD_LIBRARY_PATH="/opt/glibc/lib:/opt/glibc/lib64:$LD_LIBRARY_PATH"

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
ENV chip_example_url="https://github.com/home-assistant-libs/matter-linux-ota-provider/releases/download/2024.7.2"

# Download and install the Matter OTA provider app for ARM64
RUN set -e && \
    curl -Lo /usr/local/bin/chip-ota-provider-app --retry 5 --fail "${chip_example_url}/chip-ota-provider-app-aarch64" && \
    chmod +x /usr/local/bin/chip-ota-provider-app

# Install the custom Python Matter server
RUN pip3 install --no-cache-dir "custom-python-matter-server[server]==${PYTHON_MATTER_SERVER}"

# Define volumes and expose ports
VOLUME ["/data"]
EXPOSE 5580

# Set the entry point and default command
ENTRYPOINT ["matter-server"]
CMD ["--storage-path", "/data", "--paa-root-cert-dir", "/data/credentials"]
