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
RUN npm install -g typescript@latest

###### LIBRESPOT START ######
FROM base AS librespot
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout e68bbbf7312eca6dfd2c8b62c9b4b1f460983992
WORKDIR /librespot
RUN cargo build --release --no-default-features -j $(( $(nproc) -1 ))
###### LIBRESPOT END ######

###### SNAPCAST BUNDLE START ######
FROM base AS snapcast

### SNAPSERVER ###
RUN git clone https://github.com/badaix/snapcast.git /snapcast \
    && cd snapcast \
    && git checkout c9bdceb1342a5776a21623992885b2f96de3f398 \
    && sed -i "s/\-\-use-stderr //" "./server/streamreader/airplay_stream.cpp"
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
RUN git checkout 845219c74cd0e35cd344da9f0a37c6e7d3e576f2 \
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
    && git checkout a6c66db2761619456e80611d2ffc6054684f9caf
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
RUN apk add --no-cache  alsa-lib \
                        avahi-libs \
                        avahi \
                        avahi-tools \
                        dbus \
                        flac \
                        ffmpeg-libs \
                        glib \
                        libgcc \
                        libvorbis \
                        libuuid \
                        libgcrypt \
                        libsodium \
                        libplist \
                        libconfig \
                        musl \
                        opus \
                        soxr \
                        popt \
                        htop
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
