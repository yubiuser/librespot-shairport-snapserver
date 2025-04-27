# syntax=docker/dockerfile:1
ARG alpine_version=3.21
ARG S6_OVERLAY_VERSION=3.2.0.2

###### LIBRESPOT START ######
# Build stage for librespot
FROM docker.io/alpine:${alpine_version} AS librespot
# Declare ARG inside the stage
ARG TARGETPLATFORM

RUN apk add --no-cache \
    git \
    curl \
    libgcc \
    gcc \
    musl-dev

# Clone librespot and checkout the specific commit
RUN git clone https://github.com/librespot-org/librespot \
    && cd librespot \
    && git checkout 98e9703edbeb2665c9e8e21196d382a7c81e12cd
WORKDIR /librespot

# Setup rust toolchain
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal --default-toolchain nightly

# Install the source code for the standard library as we re-build it with the nightly toolchain
RUN rustup component add rust-src --toolchain nightly

# Size optimizations from https://github.com/johnthagen/min-sized-rust
# Strip debug symbols, build a static binary, optimize for size, enable thin LTO, abort on panic
ENV RUSTFLAGS="-C strip=symbols -C target-feature=+crt-static -C opt-level=z -C embed-bitcode=true -C lto=thin -C panic=abort"
# Use the new "sparse" protocol which speeds up the cargo index update massively
# https://blog.rust-lang.org/inside-rust/2023/01/30/cargo-sparse-protocol.html
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
# Disable incremental compilation
ENV CARGO_INCREMENTAL=0

# Build the binary, optimize libstd with build-std
# Determine Rust target dynamically based on TARGETPLATFORM
RUN echo ">>> DEBUG Librespot Stage: Received TARGETPLATFORM='${TARGETPLATFORM}'" \
    && export TARGETARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && echo ">>> DEBUG: Derived TARGETARCH='${TARGETARCH}'" \
    && case ${TARGETARCH} in \
    amd64)  RUST_TARGET=x86_64-unknown-linux-musl ;; \
    arm64)  RUST_TARGET=aarch64-unknown-linux-musl ;; \
    arm/v7) RUST_TARGET=armv7-unknown-linux-musleabihf ;; \
    *) echo >&2 "!!! ERROR: Unsupported architecture: '${TARGETARCH}' (derived from TARGETPLATFORM: '${TARGETPLATFORM}')" && exit 1 ;; \
    esac \
    && echo "Building librespot for ${RUST_TARGET} (TARGETPLATFORM: ${TARGETPLATFORM})" \
    && cargo +nightly build \
    -Z build-std=std,panic_abort \
    -Z build-std-features="optimize_for_size,panic_immediate_abort" \
    --release --no-default-features --features with-avahi -j $(nproc) \
    --target ${RUST_TARGET} \
    # Copy artifact to a fixed location for easier final copy
    && mkdir -p /app/bin \
    && cp target/${RUST_TARGET}/release/librespot /app/bin/

###### LIBRESPOT END ######

###### SNAPSERVER BUNDLE START ######
# Build stage for snapserver and its dependencies
FROM docker.io/alpine:${alpine_version} AS snapserver

### ALSA STATIC ###
RUN apk add --no-cache \
    automake \
    autoconf \
    build-base \
    bash \
    git \
    libtool \
    linux-headers \
    m4

RUN git clone https://github.com/alsa-project/alsa-lib.git /alsa-lib
WORKDIR /alsa-lib
RUN libtoolize --force --copy --automake \
    && aclocal \
    && autoheader \
    && automake --foreign --copy --add-missing \
    && autoconf \
    && ./configure --enable-shared=no --enable-static=yes CFLAGS="-ffunction-sections -fdata-sections" \
    && make -j $(( $(nproc) -1 )) \
    && make install
### ALSA STATIC END ###

WORKDIR /

### SOXR ###
RUN apk add --no-cache \
    build-base \
    cmake \
    git

RUN git clone https://github.com/chirlu/soxr.git /soxr
WORKDIR /soxr
RUN mkdir build \
    && cd build \
    && cmake -Wno-dev   -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_OPENMP=OFF \
    -DBUILD_TESTS=OFF \
    -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make -j $(( $(nproc) -1 )) \
    && make install
### SOXR END ###

WORKDIR /

### LIBEXPAT STATIC ###
RUN apk add --no-cache \
    build-base \
    bash \
    cmake \
    git

RUN git clone https://github.com/libexpat/libexpat.git /libexpat
WORKDIR /libexpat/expat
RUN mkdir build \
    && cd build \
    && cmake    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DEXPAT_BUILD_TESTS=OFF \
    -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make -j $(( $(nproc) -1 )) \
    && make install
### LIBEXPAT STATIC END ###

WORKDIR /

### LIBOPUS STATIC ###
RUN apk add --no-cache \
    build-base \
    cmake \
    git

RUN git clone https://gitlab.xiph.org/xiph/opus.git /opus
WORKDIR /opus
RUN mkdir build \
    && cd build \
    && cmake    -DOPUS_BUILD_PROGRAMS=OFF \
    -DOPUS_BUILD_TESTING=OFF \
    -DOPUS_BUILD_SHARED_LIBRARY=OFF \
    -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make -j $(( $(nproc) -1 )) \
    && make install
### LIBOPUS STATIC END ###

WORKDIR /

### FLAC STATIC ###
RUN apk add --no-cache \
    build-base \
    cmake \
    git \
    pkgconfig

RUN git clone https://github.com/xiph/flac.git /flac
RUN git clone https://github.com/xiph/ogg /flac/ogg
WORKDIR /flac
RUN mkdir build \
    && cd build \
    && cmake    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_DOCS=OFF \
    -DINSTALL_MANPAGES=OFF \
    -DCMAKE_CXX_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make \
    && make install
### FLAC STATIC END ###

WORKDIR /

### LIBVORBIS STATIC ###

# NOTE: libvorbis requires libogg (which is built as part of the flac build)
RUN apk add --no-cache \
    build-base \
    cmake \
    git

RUN git clone https://gitlab.xiph.org/xiph/vorbis.git /vorbis
WORKDIR /vorbis
RUN mkdir build \
    && cd build \
    && cmake -DCMAKE_CXX_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make -j $(( $(nproc) -1 )) \
    && make install
### LIBVORBIS STATIC END ###

WORKDIR /

### SNAPSERVER ###
RUN apk add --no-cache \
    avahi-dev \
    bash \
    build-base \
    boost-dev \
    cmake \
    git \
    npm \
    openssl-dev

RUN git clone https://github.com/badaix/snapcast.git /snapcast \
    && cd snapcast \
    && git checkout 9fbf273caa4bd9be66bed03e20c5f605ecdaca6d
WORKDIR /snapcast
RUN cmake -S . -B build \
    -DBUILD_CLIENT=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_CXX_FLAGS="-s -ffunction-sections -fdata-sections -static-libgcc -static-libstdc++ -Wl,--gc-sections " \
    && cmake --build build -j $(( $(nproc) -1 )) --verbose
WORKDIR /

# Gather all shared libaries necessary to run the executable
RUN mkdir /snapserver-libs \
    && ldd /snapcast/bin/snapserver | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp --dereference '{}' /snapserver-libs/
### SNAPSERVER END ###

### SNAPWEB ###
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout a9180a79d9cec13b6a3454d78d854637f8d7691a
ENV GENERATE_SOURCEMAP="false"
RUN npm install -g npm@latest \
    && npm ci \
    && npm run build
WORKDIR /
### SNAPWEB END ###
###### SNAPSERVER BUNDLE END ######

###### SHAIRPORT BUNDLE START ######
# Build stage for shairport-sync and its dependencies
FROM docker.io/alpine:${alpine_version} AS shairport

RUN apk add --no-cache \
    alpine-sdk \
    alsa-lib-dev \
    autoconf \
    automake \
    avahi-dev \
    dbus \
    ffmpeg-dev \
    git \
    libtool \
    libdaemon-dev \
    libplist-dev \
    libsodium-dev \
    libgcrypt-dev \
    libconfig-dev \
    openssl-dev \
    popt-dev \
    soxr-dev \
    xmltoman \
    xxd

### NQPTP ###
RUN git clone https://github.com/mikebrady/nqptp
WORKDIR /nqptp
RUN git checkout 0742bba8ed37159b6a79d7d1321a3b83de6e0bab \
    && autoreconf -i \
    && ./configure \
    && make -j $(( $(nproc) -1 ))
WORKDIR /
### NQPTP END ###

### ALAC ###
RUN git clone https://github.com/mikebrady/alac
WORKDIR /alac
RUN git checkout 1832544d27d01335d823d639b176d1cae25ecfd4 \
    && autoreconf -i \
    && ./configure \
    && make -j $(( $(nproc) -1 )) \
    && make install
WORKDIR /
### ALAC END ###

### SPS ###
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport \
    && cd /shairport \
    && git checkout c32256501f31f5b3913fbc2ee0dfbaf1ff1338f5
WORKDIR /shairport/build
RUN autoreconf -i ../ \
    && ../configure --sysconfdir=/etc \
    --with-soxr \
    --with-avahi \
    --with-ssl=openssl \
    --with-airplay-2 \
    --with-stdout \
    --with-metadata \
    --with-apple-alac \
    && DESTDIR=install make -j $(( $(nproc) -1 )) install

WORKDIR /

# Gather all shared libaries necessary to run the executable
RUN mkdir /shairport-libs \
    && ldd /shairport/build/install/usr/local/bin/shairport-sync | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp --dereference '{}' /shairport-libs/
### SPS END ###
###### SHAIRPORT BUNDLE END ######

###### BASE START ######
# Intermediate stage for common libraries and s6 setup
FROM docker.io/alpine:${alpine_version} AS base
# Declare ARGs needed within this stage
ARG TARGETARCH
ARG S6_OVERLAY_VERSION

RUN apk add --no-cache \
    avahi \
    dbus \
    fdupes
# Copy all necessary libaries into one directory
COPY --from=snapserver /snapserver-libs/ /tmp-libs/
COPY --from=shairport /shairport-libs/ /tmp-libs/
# Remove duplicates
RUN fdupes -rdN /tmp-libs/

# Install s6-overlay dynamically based on TARGETARCH
RUN apk add --no-cache --virtual .fetch-deps curl \
    && echo ">>> DEBUG Base Stage: TARGETARCH='${TARGETARCH}'" \
    && case ${TARGETARCH} in \
    amd64)  S6_ARCH=x86_64 ;; \
    arm64)  S6_ARCH=aarch64 ;; \
    arm/v7) S6_ARCH=armhf ;; \
    *) echo >&2 "!!! ERROR Base Stage: Unsupported architecture for S6: '${TARGETARCH}'" && exit 1 ;; \
    esac \
    && echo "Downloading S6 overlay for arch ${S6_ARCH}" \
    && curl -o /tmp/s6-overlay-noarch.tar.xz -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
    && curl -o /tmp/s6-overlay-arch.tar.xz -L https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && apk del .fetch-deps \
    && rm -rf /tmp/*
###### BASE END ######

###### MAIN BASE START ######
# Intermediate stage with common runtime components for both final images
FROM docker.io/alpine:${alpine_version} AS main-base

ENV S6_CMD_WAIT_FOR_SERVICES=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

# Install common runtime dependencies (excluding Python)
RUN apk add --no-cache \
    avahi \
    dbus \
    # Add any other common runtime packages here if needed
    && rm -rf /var/cache/apk/*

# Copy extracted s6-overlay components and shared libs from base stage
COPY --from=base /command /command/
COPY --from=base /package/ /package/
COPY --from=base /etc/s6-overlay/ /etc/s6-overlay/
COPY --from=base init /init
COPY --from=base /tmp-libs/ /usr/lib/

# Copy core application binaries from their respective build stages
COPY --from=librespot /app/bin/librespot /usr/local/bin/
COPY --from=snapserver /snapcast/bin/snapserver /usr/local/bin/
COPY --from=snapserver /snapweb/dist /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/install/usr/local/bin/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/

# Copy common S6 service definitions
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d

# Common runtime setup
RUN mkdir -p /var/run/dbus/
# Ensure common startup script is executable (adjust path if needed)
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

###### MAIN BASE END ######


###### SLIM FINAL STAGE ######
# Final stage for the "slim" image (without Python/Plugins)
FROM main-base AS slim

# No Python installation or plugin copy here

# Final image setup
WORKDIR /
ENTRYPOINT ["/init"]
###### SLIM FINAL STAGE END ######


###### FULL FINAL STAGE (DEFAULT) ######
# Final stage for the "full" image (with Python/Plugins)
# This is the default target if --target is not specified during build
FROM main-base AS full

# Add Python-specific dependencies
RUN echo "@testing https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories \
    && apk add --no-cache \
    # Install python dependencies for control scripts
    python3 \
    py3-pip \
    py3-gobject3 \
    py3-mpd2@testing \
    #py3-mpd2 \
    py3-musicbrainzngs \
    py3-websocket-client \
    py3-requests \
    # Clean apk cache after adding packages
    && rm -rf /var/cache/apk/* \
    # Optional: Remove the testing repository if no longer needed
    && sed -i '/@testing/d' /etc/apk/repositories

# Optional: Copy Snapcast Plugins
COPY --from=snapserver /snapcast/server/etc/plug-ins /usr/share/snapserver/plug-ins

# Final image setup
WORKDIR /
ENTRYPOINT ["/init"]
###### FULL FINAL STAGE END ######