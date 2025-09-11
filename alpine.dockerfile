# syntax=docker/dockerfile:1
ARG S6_OVERLAY_VERSION=3.2.1.0

###### LIBRESPOT START ######
FROM docker.io/alpine:3.22 AS librespot

ARG CARGO_TARGET=x86_64-unknown-linux-musl

RUN apk add --no-cache \
    git \
    curl \
    libgcc \
    gcc \
    musl-dev

# Clone librespot and checkout the latest commit
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout 2c425ebd0685820a59eac1a4206728acb8a24a51
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
RUN cargo +nightly build \
    -Z build-std=std,panic_abort \
    -Z build-std-features="optimize_for_size,panic_immediate_abort" \
    --release --no-default-features --features with-avahi -j $(( $(nproc) -1 ))\
    --target ${CARGO_TARGET}

###### LIBRESPOT END ######

###### SNAPSERVER BUNDLE START ######
FROM docker.io/alpine:3.22 AS snapserver

### ALSA STATIC ###
# Disable ALSA static build as of https://github.com/alsa-project/alsa-lib/pull/459 static build on musl is broken
# RUN apk add --no-cache \
#     automake \
#     autoconf \
#     build-base \
#     bash \
#     git \
#     libtool \
#     linux-headers \
#     m4

# RUN git clone https://github.com/alsa-project/alsa-lib.git /alsa-lib
# WORKDIR /alsa-lib
# RUN libtoolize --force --copy --automake \
#     && aclocal \
#     && autoheader \
#     && automake --foreign --copy --add-missing \
#     && autoconf \
#     && ./configure --enable-shared=no --enable-static=yes CFLAGS="-ffunction-sections -fdata-sections" \
#     && make \
#     && make install
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

RUN git clone https://github.com/xiph/opus.git /opus
WORKDIR /opus
RUN mkdir build \
    && cd build \
    && cmake    -DOPUS_BUILD_PROGRAMS=OFF \
                -DOPUS_BUILD_TESTING=OFF \
                -DOPUS_BUILD_SHARED_LIBRARY=OFF \
                -DCMAKE_C_FLAGS="-ffunction-sections -fdata-sections" .. \
    && make \
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
    && git checkout 8b7ac6986f2b37efba8087c05e35248649489d9e
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
    && ldd /snapcast/bin/snapserver | cut -d" " -f3 | xargs cp --dereference --target-directory=/snapserver-libs/
### SNAPSERVER END ###

### SNAPWEB ###
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout d2754de749ce69509207a5a403c90174f7c9853b
ENV GENERATE_SOURCEMAP="false"
RUN npm install -g npm@latest \
    && npm ci \
    && npm run build
WORKDIR /
### SNAPWEB END ###
###### SNAPSERVER BUNDLE END ######

###### SHAIRPORT BUNDLE START ######
FROM docker.io/alpine:3.22 AS shairport

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
RUN git checkout c82f64ffd02d88a4961953b50ec392090032592c \
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
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport\
    && cd /shairport \
    && git checkout d40e499de56a44371976aaf2d62b0532af5b9cc9
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
    && ldd /shairport/build/shairport-sync | cut -d" " -f3 | xargs cp --dereference --target-directory=/shairport-libs/
### SPS END ###
###### SHAIRPORT BUNDLE END ######

###### BASE START ######
FROM docker.io/alpine:3.22 AS base
ARG S6_OVERLAY_VERSION
ARG S6_ARCH=x86_64

RUN apk add --no-cache \
    avahi \
    dbus \
    fdupes
# Copy all necessary libaries into one directory to avoid carring over duplicates
# Removes all libaries that will be installed in the final image
COPY --from=snapserver /snapserver-libs/ /tmp-libs/
COPY --from=shairport /shairport-libs/ /tmp-libs/
RUN fdupes -d -N /tmp-libs/ /usr/lib/

# Install s6
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
    https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz /tmp/
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-${S6_ARCH}.tar.xz \
    && rm -rf /tmp/*

###### BASE END ######

###### MAIN START ######
FROM docker.io/alpine:3.22
ARG CARGO_TARGET=x86_64-unknown-linux-musl

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
COPY --from=librespot /librespot/target/${CARGO_TARGET}/release/librespot /usr/local/bin/
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
