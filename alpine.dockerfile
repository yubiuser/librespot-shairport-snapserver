ARG alpine_version=3.19
ARG S6_OVERLAY_VERSION=3.1.6.2

FROM docker.io/alpine:${alpine_version} as builder
RUN apk add --no-cache \
    # LIBRESPOT
    cargo \
    git \
    llvm16-libs \
    mold \
    musl-dev\
    pkgconfig \
    # SNAPCAST
    cmake \
    alsa-lib-dev \
    avahi-dev \
    bash \
    boost-dev \
    expat-dev \
    flac-dev \
    git \
    libvorbis-dev \
    npm \
    soxr-dev \
    opus-dev \
    # SHAIRPORT
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

###### LIBRESPOT START ######
FROM builder AS librespot
# Use faster 'mold' linker and strip debug symbols
ENV RUSTFLAGS="-C link-args=-fuse-ld=mold -C strip=symbols"
# Use the new "sparse" protocol which speeds up the cargo index update massively
# https://blog.rust-lang.org/inside-rust/2023/01/30/cargo-sparse-protocol.html
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
# Disable incremental compilation
ENV CARGO_INCREMENTAL=0
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout 886617e41c2177d0cb184cb761aa64acc8695a88
WORKDIR /librespot
RUN cargo build --release --no-default-features --features with-dns-sd -j $(( $(nproc) -1 ))

# Gather all shared libaries necessary to run the executable
RUN mkdir /librespot-libs \
    && ldd /librespot/target/release/librespot | cut -d" " -f3 | xargs cp --dereference --target-directory=/librespot-libs/
###### LIBRESPOT END ######

###### SNAPCAST BUNDLE START ######
FROM builder AS snapcast

### SNAPSERVER ###
RUN git clone https://github.com/badaix/snapcast.git /snapcast \
    && cd snapcast \
    && git checkout 2c575370526fa58a224bd82bf2ee614023378f37 \
    && sed -i 's/LOG(INFO, LOG_TAG) << "Waiting for metadata/LOG(DEBUG, LOG_TAG) << "Waiting for metadata/' "./server/streamreader/airplay_stream.cpp"
WORKDIR /snapcast
RUN cmake -S . -B build -DBUILD_CLIENT=OFF \
    && cmake --build build -j $(( $(nproc) -1 )) --verbose \
    && strip -s ./bin/snapserver
WORKDIR /

# Gather all shared libaries necessary to run the executable
RUN mkdir /snapserver-libs \
    && ldd /snapcast/bin/snapserver | cut -d" " -f3 | xargs cp --dereference --target-directory=/snapserver-libs/
### SNAPSERVER END ###

### SNAPWEB ###
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout 40590affd29ffdcf74768e2b06d67c2241676abb
ENV GENERATE_SOURCEMAP="false"
RUN npm install -g npm@latest \
    && npm ci \
    && npm run build
WORKDIR /
### SNAPWEB END ###
###### SNAPCAST BUNDLE END ######

###### SHAIRPORT BUNDLE START ######
FROM builder AS shairport

### NQPTP ###
RUN git clone https://github.com/mikebrady/nqptp
WORKDIR /nqptp
RUN git checkout 5fb99599d87f09a38497c698173b46ac901ec7ce \
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

### SPS ###
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport\
    && cd /shairport \
    && git checkout e36ec5c45d872cd1bdc59a24b805560b5e7029aa
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
FROM docker.io/alpine:${alpine_version} as base
ARG S6_OVERLAY_VERSION
RUN apk add --no-cache \
    avahi \
    dbus \
    fdupes
# Copy all necessary libaries into one directory to avoid carring over duplicates
# Removes all libaries that will be installed in the final image
COPY --from=librespot /librespot-libs/ /tmp-libs/
COPY --from=snapcast /snapserver-libs/ /tmp-libs/
COPY --from=shairport /shairport-libs/ /tmp-libs/
RUN fdupes -d -N /tmp-libs/ /usr/lib/

# Install s6
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz \
    https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz \
    && rm -rf /tmp/*

###### BASE END ######

###### MAIN START ######
FROM docker.io/alpine:${alpine_version}

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
COPY --from=librespot /librespot/target/release/librespot /usr/local/bin/
COPY --from=snapcast /snapcast/bin/snapserver /usr/local/bin/
COPY --from=snapcast /snapweb/build /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/

# Copy local files
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

RUN mkdir -p /var/run/dbus/

ENTRYPOINT ["/init"]
###### MAIN END ######
