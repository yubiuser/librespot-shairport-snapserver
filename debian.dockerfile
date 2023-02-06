###### LIBRESPOT START ######
FROM docker.io/debian:bullseye-slim AS librespot
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        build-essential \
        ca-certificates \
        curl \
        git \
        pkg-config \
        libasound2-dev
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin/:${PATH}"
RUN git clone https://github.com/librespot-org/librespot \
   && cd librespot \
   && git checkout e68bbbf7312eca6dfd2c8b62c9b4b1f460983992
WORKDIR /librespot
RUN cargo build --release --no-default-features -j $(( $(nproc) -1 ))
###### LIBRESPOT END ######

###### SNAPCAST START ######
FROM docker.io/debian:bullseye-slim AS snapcast
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        build-essential \
        ca-certificates \
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
        libexpat1-dev

### SNAPSERVER ###
RUN git clone https://github.com/badaix/snapcast.git /snapcast \
    && cd snapcast \
    && git checkout c9bdceb1342a5776a21623992885b2f96de3f398 \
    && sed -i "s/\-\-use-stderr //" "./server/streamreader/airplay_stream.cpp"
WORKDIR /snapcast
RUN  make HAS_EXPAT=1 -j $(( $(nproc) -1 )) server #https://github.com/badaix/snapcast/commit/fdcdf8e350e10374452a091fc8fa9e50641b9e86
WORKDIR /
### SNAPSERVER END ###

### SNAPWEB ###
RUN npm install -g typescript@latest
RUN git clone https://github.com/badaix/snapweb.git
WORKDIR /snapweb
RUN git checkout f19a12a3c27d0a4fcbb1058f365f36973c09d033
RUN make
WORKDIR /
### SNAPWEB END ###
###### SNAPCAST END ######

###### SHAIRPORT START ######
FROM docker.io/debian:bullseye-slim AS shairport
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
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
###### SHAIRPORT END ######

###### MAIN START ######
FROM docker.io/debian:bullseye-slim
ARG S6_OVERLAY_VERSION=3.1.3.0
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        ca-certificates \
        avahi-daemon \
        dbus\
        xz-utils \
        libvorbis0a \
        libvorbisenc2 \
        libflac8 \
        libopus0 \
        libsoxr0 \
        libasound2 \
        libavahi-client3 \
        libswresample3 \
        libavcodec-extra58 \
        libsodium23 \
        libplist3 \
        libconfig9 \
        libpopt0 \
    && apt-get clean

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz


# Copy all necessary files from the builders
COPY --from=librespot /librespot/target/release/librespot /usr/local/bin/
COPY --from=snapcast /snapcast/server/snapserver /usr/local/bin/
COPY --from=snapcast /snapweb/dist /usr/share/snapserver/snapweb
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

###### MAIN END ######
