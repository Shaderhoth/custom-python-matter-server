FROM python:3.12-slim-bookworm

# Set the shell for better error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Set working directory
WORKDIR /app

# Install essential build tools and required dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    wget \
    gawk \
    bison \
    perl \
    texinfo \
    manpages-dev \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev

# Download glibc source
RUN wget --progress=dot:giga --retry-connrefused --timeout=20 http://ftp.gnu.org/gnu/libc/glibc-2.38.tar.gz && \
    tar -xvzf glibc-2.38.tar.gz && \
    rm glibc-2.38.tar.gz

# Configure glibc with adjustments for safety and debugging
RUN cd glibc-2.38 && \
    mkdir build && cd build && \
    ../configure --prefix=/usr --disable-werror --disable-stack-protector --enable-stackguard-randomization --enable-debug || cat config.log

# Build glibc with limited jobs and verbose output
RUN cd glibc-2.38/build && \
    make -j1 V=1 || (echo "Build failed. Printing log:" && tail -n 1000 config.log && exit 1)

# Modify the Makefile to skip problematic targets and log the output
RUN sed -i '/sotruss-lib.so/d' glibc-2.38/elf/Makefile && \
    sed -i '/recipe commences before first target/d' glibc-2.38/elf/Makefile

# Install glibc with verbose output
RUN cd glibc-2.38/build && \
    make -j1 install V=1 || (echo "Install failed. Printing logs:" && tail -n 1000 config.log && exit 1)

# Clean up build dependencies and artifacts
RUN apt-get purge -y perl texinfo manpages-dev libmpc-dev libmpfr-dev libgmp-dev && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /app/glibc-2.38*


# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
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
