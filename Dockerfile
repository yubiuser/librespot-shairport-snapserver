# syntax=docker/dockerfile:1
ARG S6_OVERLAY_VERSION=3.2.3.1

###### LIBRESPOT START ######
FROM docker.io/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS librespot

ARG TARGETARCH

RUN apk add --no-cache \
    git \
    curl \
    libgcc \
    gcc \
    musl-dev

# Clone librespot and checkout the latest commit
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout 33bf3a77ed4b549df67e8347d7d6e55b007b3ec2
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
ENV RUSTFLAGS="-C strip=symbols -C target-feature=+crt-static -C opt-level=z -C embed-bitcode=true -C lto=thin -Z unstable-options -C panic=immediate-abort"
# Use the new "sparse" protocol which speeds up the cargo index update massively
# https://blog.rust-lang.org/inside-rust/2023/01/30/cargo-sparse-protocol.html
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
# Disable incremental compilation
ENV CARGO_INCREMENTAL=0

# Build the binary, optimize libstd with build-std
# Set CARGO_TARGET based on TARGETARCH
RUN case "${TARGETARCH}" in \
      amd64) CARGO_TARGET="x86_64-unknown-linux-musl" ;; \
      arm64) CARGO_TARGET="aarch64-unknown-linux-musl" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && cargo +nightly build \
        -Z build-std=std,panic_abort \
        -Z build-std-features="optimize_for_size" \
        --release --no-default-features --features "with-avahi rustls-tls-webpki-roots" -j $(nproc) \
        --target ${CARGO_TARGET} \
    && mkdir -p /output \
    && cp target/${CARGO_TARGET}/release/librespot /output/librespot

###### LIBRESPOT END ######

###### SNAPSERVER BUNDLE START ######
FROM docker.io/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS snapserver

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
    && make \
    && make install
### ALSA STATIC END ###

WORKDIR /

### SOXR ###
RUN apk add --no-cache \
    build-base \
    cmake \
    git

# Not using the real sox repo athttps://sourceforge.net/p/soxr/code/merge-requests/ because
# it is very outdated and does not compile on modern systems (e.g. CMAKE > 3.5)
RUN git clone https://github.com/dofuuz/soxr /soxr
WORKDIR /soxr
RUN mkdir build \
    && cd build \
    && cmake -Wno-dev   -DCMAKE_BUILD_TYPE=Release \
                        -DBUILD_SHARED_LIBS=OFF \
                        -DWITH_OPENMP=OFF \
                        -DBUILD_TESTS=OFF \
                        -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make -j $(nproc) \
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
    && make -j $(nproc) \
    && make install
### LIBEXPAT STATIC END ###

WORKDIR /

### LIBOPUS STATIC ###
RUN apk add --no-cache \
    build-base \
    cmake \
    git

RUN git clone https://github.com/xiph/opus.git /opus
WORKDIR /opus
RUN mkdir build \
    && cd build \
    && cmake    -DOPUS_BUILD_PROGRAMS=OFF \
                -DOPUS_BUILD_TESTING=OFF \
                -DOPUS_BUILD_SHARED_LIBRARY=OFF \
                -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make -j $(nproc) \
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
    && make -j $(nproc) \
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
    && make \
    && make install
### LIBVORBIS STATIC END ###

WORKDIR /

### SNAPSERVER ###
RUN apk add --no-cache \
    alsa-lib-dev \
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
    && git checkout f12373479243e93a97237592d6a3703539ec41d5
WORKDIR /snapcast
RUN cmake -S . -B build \
    -DBUILD_CLIENT=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_CXX_FLAGS="-s -ffunction-sections -fdata-sections -static-libgcc -static-libstdc++ -Wl,--gc-sections " \
    && cmake --build build -j $(nproc) --verbose
WORKDIR /

# Gather all shared libaries necessary to run the executable
RUN mkdir /snapserver-libs \
    && ldd /snapcast/bin/snapserver | cut -d" " -f3 | xargs cp --dereference --target-directory=/snapserver-libs/
### SNAPSERVER END ###

### SNAPWEB ###
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout 9acee022e41da4974ad5f001e61f185dbad76917
ENV GENERATE_SOURCEMAP="false"
RUN npm install -g npm@latest \
    && npm install \
    && npm ci \
    && npm run build
WORKDIR /
### SNAPWEB END ###
###### SNAPSERVER BUNDLE END ######

###### SHAIRPORT BUNDLE START ######
FROM docker.io/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS shairport

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
    libplist-util \
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
RUN git checkout c17af00b40a454596ca43e1855c9aa13529ebc1f \
    && autoreconf -i \
    && ./configure \
    && make -j $(nproc)
WORKDIR /
### NQPTP END ###

### SPS ###
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport\
    && cd /shairport \
    && git checkout c3443a13be183e0467190a6dfc574c210a25cacc
WORKDIR /shairport/build
RUN autoreconf -i ../ \
    && ../configure --sysconfdir=/etc \
                    --with-soxr \
                    --with-avahi \
                    --with-ssl=openssl \
                    --with-airplay-2 \
                    --with-stdout \
                    --with-metadata \
    && DESTDIR=install make -j $(nproc) install

WORKDIR /

# Gather all shared libaries necessary to run the executable
RUN mkdir /shairport-libs \
    && ldd /shairport/build/shairport-sync | cut -d" " -f3 | xargs cp --dereference --target-directory=/shairport-libs/
### SPS END ###
###### SHAIRPORT BUNDLE END ######

###### BASE START ######
FROM docker.io/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS base
ARG S6_OVERLAY_VERSION
ARG TARGETARCH

RUN apk add --no-cache \
    avahi \
    dbus \
    fdupes
# Copy all necessary libaries into one directory to avoid carring over duplicates
# Removes all libaries that will be installed in the final image
COPY --from=snapserver /snapserver-libs/ /tmp-libs/
COPY --from=shairport /shairport-libs/ /tmp-libs/
RUN fdupes -d -N /tmp-libs/ /usr/lib/

# Install s6 - map Docker's TARGETARCH to s6-overlay architecture names
RUN case "${TARGETARCH}" in \
      amd64) S6_ARCH="x86_64" ;; \
      arm64) S6_ARCH="aarch64" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" && exit 1 ;; \
    esac \
    && wget -O /tmp/s6-overlay-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    && wget -O /tmp/s6-overlay-arch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz \
    && rm -rf /tmp/*

###### BASE END ######

###### MAIN START ######
FROM docker.io/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

ENV S6_CMD_WAIT_FOR_SERVICES=1
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

RUN apk add --no-cache \
            avahi \
            dbus \
    && rm -rf /lib/apk/db/*

# Copy extracted s6-overlay and libs from base
COPY --from=base /command /command/
COPY --from=base /package/ /package/
COPY --from=base /etc/s6-overlay/ /etc/s6-overlay/
COPY --from=base init /init
COPY --from=base /tmp-libs/ /usr/lib/

# Copy all necessary files from the builders
COPY --from=librespot /output/librespot /usr/local/bin/
COPY --from=snapserver /snapcast/bin/snapserver /usr/local/bin/
COPY --from=snapserver /snapweb/dist /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/

# Copy local files
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

RUN mkdir -p /var/run/dbus/

ENTRYPOINT ["/init"]
###### MAIN END ######
