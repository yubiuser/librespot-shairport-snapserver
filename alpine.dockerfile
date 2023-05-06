FROM docker.io/alpine:3.17 as base
RUN apk add --no-cache \
    # LIBRESPOT
    git \
    mold \
    musl-dev\
    pkgconfig \
    # SNAPCAST
    alpine-sdk \
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
FROM base AS librespot
# Use faster 'mold' linker from 'edge'
RUN apk add --no-cache llvm16-libs --repository=https://dl-cdn.alpinelinux.org/alpine/edge/main
ENV RUSTFLAGS="-C link-args=-fuse-ld=mold -C strip=symbols"
# Install cargo/rust from 'edge' as it is >= v1.68 which uses the new "sparse" protocol which speeds up the cargo index update massively
RUN apk add --no-cache cargo --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community
# https://blog.rust-lang.org/inside-rust/2023/01/30/cargo-sparse-protocol.html
ENV CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
# Disable incremental compilation
ENV CARGO_INCREMENTAL=0
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout e4d476533203b734335a07bd0342fabb9ac34f42
WORKDIR /librespot
RUN cargo build --release --no-default-features --features with-dns-sd -j $(( $(nproc) -1 ))

# Gather all shared libaries necessary to run the executable
RUN mkdir /librespot-libs \
    && ldd /librespot/target/release/librespot | cut -d" " -f3 | xargs cp --dereference --target-directory=/librespot-libs/
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
    && cmake --build build -j $(( $(nproc) -1 )) --verbose \
    && strip -s ./bin/snapserver
WORKDIR /
### SNAPSERVER END ###

### SNAPWEB ###
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout a51c67e5fbef9f7f2e5c2f5002db93fcaaac703d
RUN npm ci && npm run build
WORKDIR /
### SNAPWEB END ###

# Gather all shared libaries necessary to run the executable
RUN mkdir /snapserver-libs \
    && ldd /snapcast/bin/snapserver | cut -d" " -f3 | xargs cp --dereference --target-directory=/snapserver-libs/
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

### SPS ###
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport\
    && cd /shairport \
    && git checkout a1c9387ca81bedebb986e237403db0cd57ae45dc
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

###### MAIN START ######
FROM docker.io/crazymax/alpine-s6:3.17-3.1.1.2
RUN apk add --no-cache \
            avahi \
            dbus \
    && rm -rf /lib/apk/db/*

# Copy all necessary files from the builders
COPY --from=librespot /librespot/target/release/librespot /usr/local/bin/
COPY --from=snapcast /snapcast/bin/snapserver /usr/local/bin/
COPY --from=snapcast /snapweb/build /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/
COPY --from=shairport /usr/local/lib/libalac.* /usr/local/lib/

COPY --from=librespot /librespot-libs/ /usr/lib/
COPY --from=snapcast /snapserver-libs/ /usr/lib/
COPY --from=shairport /shairport-libs/ /usr/lib/

# Copy local files
COPY snapserver.conf /etc/snapserver.conf
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

###### MAIN END ######
