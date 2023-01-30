###### LIBRESPOT ######
FROM docker.io/alpine:3.17 AS librespot
RUN apk add --no-cache  alsa-lib-dev \
                        cargo \
                        git \
                        musl-dev\
                        pkgconfig  
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout dev
WORKDIR /librespot
RUN cargo build --release -j $(( $(nproc) -1 ))
###### LIBRESPOT END ######

###### SNAPCAST BUNDLE ######
FROM docker.io/alpine:3.17 AS snapcast
RUN apk add --no-cache  alpine-sdk \
                        alsa-lib-dev \
                        avahi-dev \
                        bash \
                        boost-dev \
                        boost1.80-dev \
                        expat-dev \
                        flac-dev \
                        git \
                        libvorbis-dev \
                        npm \
                        soxr-dev \
                        opus-dev

### SNAPSERVER ###
RUN git clone https://github.com/badaix/snapcast.git /snapcast \
    && cd snapcast \
    && git checkout develop \
    && sed -i "s/\-\-use-stderr //" "./server/streamreader/airplay_stream.cpp"
WORKDIR /snapcast
RUN  make HAS_EXPAT=1 -j $(( $(nproc) -1 )) server #https://github.com/badaix/snapcast/commit/fdcdf8e350e10374452a091fc8fa9e50641b9e86
WORKDIR /
### SNAPSERVER END ###

### SNAPWEB ###
RUN npm install -g typescript@latest 
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN make
WORKDIR /
### SNAPWEB END ###
###### SNAPCAST BUNDLE END ######

###### SHAIRPORT BUNDLE ######
FROM docker.io/alpine:3.17 AS shairport
RUN apk add --no-cache  alpine-sdk \
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
RUN git checkout development \
    && autoreconf -i \
    && ./configure \
    && make -j $(( $(nproc) -1 ))
WORKDIR /
### NQPTP END ###

### ALAC ###
RUN git clone https://github.com/mikebrady/alac
WORKDIR /alac
RUN autoreconf -i \
    && ./configure \
    && make -j $(( $(nproc) -1 )) \
    && make install
WORKDIR /
### ALAC END ###

### SPS ###
RUN git clone https://github.com/mikebrady/shairport-sync.git /shairport\
    && cd /shairport \
    && git checkout development
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

###### MAIN ######
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
COPY --from=snapcast /snapcast/server/snapserver /usr/local/bin/
COPY --from=snapcast /snapweb/dist /usr/share/snapserver/snapweb
COPY --from=shairport /shairport/build/shairport-sync /usr/local/bin/
COPY --from=shairport /nqptp/nqptp /usr/local/bin/
COPY --from=shairport /shairport/build/install/etc/shairport-sync.conf /etc/
COPY --from=shairport /shairport/build/install/etc/shairport-sync.conf.sample /etc/
COPY --from=shairport /usr/local/lib/libalac.* /usr/local/lib/
COPY --from=shairport /shairport/build/install/etc/dbus-1/system.d/shairport-sync-dbus.conf /etc/dbus-1/system.d/
COPY --from=shairport /shairport/build/install/etc/dbus-1/system.d/shairport-sync-mpris.conf /etc/dbus-1/system.d/

# Copy local files
COPY snapserver.conf /etc/snapserver.conf
COPY ./s6-overlay/s6-rc.d /etc/s6-overlay/s6-rc.d
RUN chmod +x /etc/s6-overlay/s6-rc.d/01-startup/script.sh

# Create non-root user for running the container -- running as the user 'shairport-sync' also allows
# Shairport Sync to provide the D-Bus and MPRIS interfaces within the container
RUN addgroup shairport-sync \
    && adduser -D shairport-sync -G shairport-sync

EXPOSE 1704/tcp 1705/tcp

###### MAIN END ######
