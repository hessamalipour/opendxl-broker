###############################################################################
# Compile Broker
###############################################################################

FROM almalinux:8 as builder
ARG build_docs=false

# Install necessary packages (OpenSSL 1.1.x, Boost, etc.)
RUN dnf -y update \
    && dnf -y install openssl-devel boost-devel cmake libuuid-devel wget make gcc gcc-c++ \
    && dnf clean all

# Verify OpenSSL version is at most 1.1.x
RUN openssl version | grep -E 'OpenSSL 1\.1\.[0-9]' || (echo "OpenSSL 1.1.x is required" && exit 1)

# Install MessagePack (0.5.8)
RUN cd /tmp \
    && wget https://github.com/msgpack/msgpack-c/releases/download/cpp-0.5.8/msgpack-0.5.8.tar.gz \
    && tar xvfz msgpack-0.5.8.tar.gz \
    && cd msgpack-0.5.8 \
    && ./configure \
    && make \
    && make install

# Install JsonCPP (1.6.0)
RUN cd /tmp \
    && wget https://github.com/open-source-parsers/jsoncpp/archive/1.6.0.tar.gz \
    && tar xvfz 1.6.0.tar.gz \
    && cd jsoncpp-1.6.0 \
    && cmake -DCMAKE_BUILD_TYPE=release -DBUILD_STATIC_LIBS=ON -DBUILD_SHARED_LIBS=OFF \
        -DARCHIVE_INSTALL_DIR=/usr/local/lib -G "Unix Makefiles" \
    && make \
    && make install

# Build the broker
COPY src /tmp/src
RUN cd /tmp/src && make

# Generate documentation if build_docs is true
COPY docs /tmp/docs
RUN mkdir /tmp/docs-output
RUN if [ "$build_docs" = "true" ]; then \
        dnf -y install flex bison python3 doxygen \
        && dnf clean all \
        && cd /tmp/docs \
        && . /tmp/src/version \
        && sed -i "s,@PROJECT_NUMBER@,$SOMAJVER.$SOMINVER.$SOSUBMINVER.$SOBLDNUM,g" doxygen.config \
        && doxygen doxygen.config > /tmp/docs-output/build.log 2>&1; \
    fi

###############################################################################
# Build Broker Image
###############################################################################

FROM almalinux:8

ARG DXL_CONSOLE_VERSION=0.2.2

# Install runtime dependencies
RUN dnf update -y && \
    dnf install -y \
    util-linux \
    iproute \
    procps-ng \
    python3.11 \
    python3.11-devel \
    gcc \
    gcc-c++ \
    make \
    ca-certificates && \
    update-ca-trust && \
    dnf clean all

# # Enable OpenSSL Debugging in Runtime Stage
# ENV OPENSSL_DEBUG=1 \
#     OPENSSL_CONF=/etc/ssl/openssl.cnf

# # Add debug settings to OpenSSL configuration
# RUN echo "[default]" >> /etc/ssl/openssl.cnf && \
#     echo "openssl_debug = debug" >> /etc/ssl/openssl.cnf

# Set Python 3.11 as the default Python version
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    alternatives --set python3 /usr/bin/python3.11

# Ensure pip is installed and upgraded for Python 3.11
RUN python3.11 -m ensurepip --upgrade && \
    python3.11 -m pip install --upgrade pip setuptools wheel

# Verify Python and pip installation
RUN python3.11 --version && python3.11 -m pip --version

# Set up Python virtual environment for the application
RUN python3 -m venv /opt/dxlconsole-env && \
    /opt/dxlconsole-env/bin/pip install --upgrade pip setuptools wheel && \
    /opt/dxlconsole-env/bin/pip install dxlconsole==0.2.2

# Fix compatibility issues with Python packages
RUN sed -i 's/from collections import Callable/from collections.abc import Callable/' \
    /opt/dxlconsole-env/lib/python3.11/site-packages/socks.py
# Replace MD5 with SHA-256 in dxlconsole/app.py
RUN sed -i 's/hashlib.md5()/hashlib.sha256()/g' \
    /opt/dxlconsole-env/lib/python3.11/site-packages/dxlconsole/app.py
RUN sed -i 's/md5.update(unique_id)/md5.update(unique_id.encode("utf-8"))/' \
    /opt/dxlconsole-env/lib/python3.11/site-packages/dxlconsole/app.py

RUN python3 -m pip install --upgrade pip
# RUN find ~/ -name "pip*"
# RUN python3 --version
# RUN pip --version

# Copy broker files and libraries
COPY dxlbroker /dxlbroker
COPY LICENSE* /dxlbroker/
COPY --from=builder /tmp/src/mqtt-core/src/dxlbroker /dxlbroker/bin
COPY --from=builder /usr/local/lib/libmsgpackc.so.2.0.0 /dxlbroker/lib

# Copy documentation
COPY --from=builder /tmp/docs-output /dxlbroker/docs

# Create volume directory
RUN mkdir /dxlbroker-volume

# Add user and set permissions
RUN useradd --home-dir /dxlbroker --create-home --shell /bin/bash dxl \
    && chown -R dxl:dxl /dxlbroker-volume \
    && chown -R dxl:dxl /dxlbroker

# Ensure startup script is executable
RUN chmod +x /dxlbroker/startup.sh

# Expose the volume
VOLUME ["/dxlbroker-volume"]

# Set the user
USER dxl

# Expose necessary ports
EXPOSE 8883
EXPOSE 8443

# Set the entrypoint
ENTRYPOINT ["/dxlbroker/startup.sh"]
