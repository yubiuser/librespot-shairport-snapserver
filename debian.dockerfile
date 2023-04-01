FROM docker.io/debian:bookworm-slim AS base
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    # LIBRESPOT
    build-essential \
    ca-certificates \
    curl \
    git \
    mold\
    libavahi-compat-libdnssd-dev \
    pkg-config \
    libasound2-dev \
    # Snapcast
    build-essential \
    ca-certificates \
    cmake \
    git \
    npm \
    libboost-dev \
    libasound2-dev \
    libpulse-dev \
    libvorbisidec-dev \
    libvorbis-dev \
    libopus-dev \
    libflac-dev \
    libsoxr-dev \
    libavahi-client-dev \
    libexpat1-dev \
    # SHAIRPORT
    build-essential \
    ca-certificates \
    git \
    autoconf \
    automake \
    libglib2.0-dev \
    libtool \
    libpopt-dev \
    libconfig-dev \
    libasound2-dev \
    libavahi-client-dev \
    libssl-dev \
    libsoxr-dev \
    libplist-dev \
    libsodium-dev \
    libavutil-dev \
    libavcodec-dev \
    libavformat-dev \
    uuid-dev \
    libgcrypt-dev \
    xxd

###### LIBRESPOT START ######
FROM base AS librespot
# Setup Rust
RUN curl https://sh.rustup.rs -sSf | sh -s -- --profile minimal -y
ENV PATH="/root/.cargo/bin/:${PATH}"
# Update cargo index fast
# https://blog.rust-lang.org/inside-rust/2023/01/30/cargo-sparse-protocol.html
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
# Disable incremental compilation
ENV CARGO_INCREMENTAL=0
# Use faster 'mold' linker
ENV RUSTFLAGS="-C link-args=-fuse-ld=mold"
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout 7de8bdc0f3a4b726e921da2fb4c4a1726b98183c
WORKDIR /librespot
RUN cargo build --release --no-default-features --features with-dns-sd -j $(( $(nproc) -1 ))
###### LIBRESPOT END ######


###### SNAPCAST BUNDLE START ######
FROM base AS snapcast

### SNAPSERVER ###
RUN git clone https://github.com/badaix/snapcast.git /snapcast \
    && cd snapcast \
    && git checkout 5968f96e11d4abf21e8b50cfe9ae306cdec29d57 \
    && sed -i 's/\-\-use-stderr //' "./server/streamreader/airplay_stream.cpp" \
    && sed -i 's/LOG(INFO, LOG_TAG) << "Waiting for metadata/LOG(DEBUG, LOG_TAG) << "Waiting for metadata/' "./server/streamreader/airplay_stream.cpp"
WORKDIR /snapcast
RUN cmake -S . -B build -DBUILD_CLIENT=OFF \
    && cmake --build build -j $(( $(nproc) -1 )) --verbose
WORKDIR /
### SNAPSERVER END ###

### SNAPWEB ###
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout 0df63b98505aaad55a1cf588176249dd5036b467
ENV GENERATE_SOURCEMAP="false"
RUN npm install -g npm@latest \
    && npm ci \
    && npm run build
WORKDIR /
### SNAPWEB END ###
###### SNAPCAST BUNDLE END ######

###### SHAIRPORT BUNDLE START ######
FROM base AS shairport

### NQPTP ###
RUN git clone https://github.com/mikebrady/nqptp
WORKDIR /nqptp
RUN git checkout 576273509779f31b9e8b4fa32087dea7105fa8c7 \
    && autoreconf -i \
    && ./configure \
    && make -j $(( $(nproc) -1 ))
WORKDIR /
### NQPTP END ###

### ALAC ###
RUN git clone https://github.com/mikebrady/alac
WORKDIR /alac
RUN git checkout 96dd59d17b776a7dc94ed9b2c2b4a37177feb3c4 \
    && autoreconf -i \
    && ./configure \
    && make -j $(( $(nproc) -1 )) \
    && make install
WORKDIR /
### ALAC END ###

### METADATA-READER START ###
RUN git clone https://github.com/mikebrady/shairport-sync-metadata-reader.git
WORKDIR /shairport-sync-metadata-reader
RUN autoreconf -i -f \
    && ./configure \
    && make
WORKDIR /
### METADATA-READER END ###

### SPS ###
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport\
    && cd /shairport \
    && git checkout 1b53d9d3068fcc39ec8a286f01312e4fc54cb1e4
WORKDIR /shairport/build
RUN autoreconf -i ../ \
    && ../configure --sysconfdir=/etc \
                    --with-soxr \
                    --with-avahi \
                    --with-ssl=openssl \
                    --with-airplay-2 \
                    --with-stdout \
                    --with-pipe \
                    --with-metadata \
                    --with-apple-alac \
                    --with-dbus-interface \
                    --with-mpris-interface \
    && DESTDIR=install make -j $(( $(nproc) -1 )) install
WORKDIR /
### SPS END ###
###### SHAIRPORT BUNDLE END ######

###### MAIN START ######
FROM docker.io/debian:bookworm-slim
ARG S6_OVERLAY_VERSION=3.1.4.1
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates \
        avahi-daemon \
        dbus\
        xz-utils \
        libvorbis0a \
        libvorbisenc2 \
        libflac12 \
        libopus0 \
        libsoxr0 \
        libasound2 \
        libavahi-client3 \
        libswresample4 \
        libavcodec-extra59 \
        libsodium23 \
        libplist3 \
        libconfig9 \
        libpopt0 \
        libnss-mdns\
        libavahi-compat-libdnssd1 \
    && apt-get clean

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz


# Copy all necessary files from the builders
COPY --from=librespot /librespot/target/release/librespot /usr/local/bin/
COPY --from=snapcast /snapcast/bin/snapserver /usr/local/bin/
COPY --from=snapcast /snapweb/build /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/
COPY --from=shairport /shairport/build/install/etc/shairport-sync.conf /etc/
COPY --from=shairport /shairport/build/install/etc/shairport-sync.conf.sample /etc/
COPY --from=shairport /usr/local/lib/libalac.* /usr/lib/
COPY --from=shairport /shairport/build/install/etc/dbus-1/system.d/shairport-sync-dbus.conf /etc/dbus-1/system.d/
COPY --from=shairport /shairport/build/install/etc/dbus-1/system.d/shairport-sync-mpris.conf /etc/dbus-1/system.d/

# Copy local files
COPY snapserver.conf /etc/snapserver.conf
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

# Create non-root user for running the container -- running as the user 'shairport-sync' also allows
# Shairport Sync to provide the D-Bus and MPRIS interfaces within the container
RUN addgroup shairport-sync \
    && adduser --disabled-password --no-create-home shairport-sync --ingroup shairport-sync

RUN mkdir /run/dbus

ENTRYPOINT ["/init"]
###### MAIN END ######
