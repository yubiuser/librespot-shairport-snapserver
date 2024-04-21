ARG alpine_version=3.19

FROM docker.io/alpine:${alpine_version} as builder
RUN apk add --no-cache \
    git \
    libtool \
    autoconf \
    automake \
    gettext-dev \
    pkgconfig

RUN git clone https://github.com/avahi/avahi
WORKDIR /avahi
RUN autoreconf -vif
RUN apk add --no-cache \
    g++ \
    glib-dev \
    dbus-dev \
    expat-dev \
    build-base
RUN
ENV LDFLAGS="$LDFLAGS -lintl"
RUN   ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --localstatedir=/var \
    --disable-autoipd \
    --disable-glib \
    --disable-gobject \
    --disable-gdbm \
    --disable-libdaemon \
    --disable-libsystemd \
    --disable-libevent \
    --disable-qt3 \
    --disable-qt4 \
    --disable-qt5 \
    --disable-gtk \
    --disable-gtk3 \
    --disable-mono \
    --disable-monodoc \
    --disable-doxygen-doc \
    --disable-manpages \
    --enable-compat-libdns_sd \
    --disable-compat-howl \
    --disable-python \
    --with-dbus-sys=/usr/share/dbus-1/system.d \
    --with-distro="gentoo"

RUN make

FROM scratch as deploy
COPY --from=builder /avahi/avahi-client/.libs/libavahi-client.a /
COPY --from=builder /avahi/avahi-common/.libs/libavahi-common.a /
COPY --from=builder /avahi/avahi-compat-libdns_sd/.libs/libdns_sd.a /
COPY --from=builder /avahi/avahi-compat-libdns_sd.pc /
