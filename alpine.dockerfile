FROM docker.io/alpine:3.17 as base
RUN apk add --no-cache \
    # LIBRESPOT
    cargo \
    git \
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
# SNAPWEB
RUN npm install -g typescript@4.9.5

###### LIBRESPOT START ######
FROM base AS librespot
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout a211ff94c6c9d11b78964aad91b2a7db1d17d04f
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
RUN git checkout f19a12a3c27d0a4fcbb1058f365f36973c09d033
RUN make
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
    && git checkout a1c9387ca81bedebb986e237403db0cd57ae45dc
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
FROM docker.io/crazymax/alpine-s6:3.17-3.1.1.2
RUN apk add --no-cache \
            # COMMON/s6
            avahi \
            dbus \
            htop \
            # LIBRESPOT
            avahi-compat-libdns_sd \
            libgcc \
            # SNAPCAST
            alsa-lib \
            flac-libs \
            libogg \
            libvorbis \
            libstdc++ \
            libgcc \
            opus \
            soxr \
            # SHAIRPORT
            ffmpeg-libs \
            glib \
            libuuid \
            libgcrypt \
            libgcc \
            libsodium \
            libplist \
            libconfig \
            popt \
            soxr

# Copy all necessary files from the builders
COPY --from=librespot /librespot/target/release/librespot /usr/local/bin/
COPY --from=snapcast /snapcast/bin/snapserver /usr/local/bin/
COPY --from=snapcast /snapweb/dist /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/
COPY --from=shairport /shairport/build/install/etc/shairport-sync.conf /etc/
COPY --from=shairport /usr/local/lib/libalac.* /usr/local/lib/
COPY --from=shairport /shairport/build/install/etc/dbus-1/system.d/shairport-sync-dbus.conf /etc/dbus-1/system.d/
COPY --from=shairport /shairport/build/install/etc/dbus-1/system.d/shairport-sync-mpris.conf /etc/dbus-1/system.d/
COPY --from=shairport /shairport-sync-metadata-reader/shairport-sync-metadata-reader  /usr/local/bin/shairport-sync-metadata-reader

# Copy local files
COPY snapserver.conf /etc/snapserver.conf
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

# Create non-root user for running the container -- running as the user 'shairport-sync' also allows
# Shairport Sync to provide the D-Bus and MPRIS interfaces within the container
RUN addgroup shairport-sync \
    && adduser -D shairport-sync -G shairport-sync

###### MAIN END ######
