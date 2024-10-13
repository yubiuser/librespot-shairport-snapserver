# librespot-shairport-snapserver

Alpine based Docker image for running the [snapserver part of snapcast](https://github.com/badaix/snapcast) with
[librespot](https://github.com/librespot-org/librespot) and [shairport-sync](https://github.com/mikebrady/shairport-sync) as input.

Idea adapted from [librespot-snapserver](https://github.com/djmaze/librespot-snapserver) and based on [shairport-sync docker image](https://github.com/mikebrady/shairport-sync/tree/master/docker)

 **Background:** When this project started, the last releases of *snapcast* and *librespot* where outdated compared to their respective `develop` branches.
  Therefore, everything is compiled from source using the development branches for all repos.

 **Note** The coresponding Docker image for runinng `snapclient` can be found here: [https://github.com/yubiuser/snapclient-docker](https://github.com/yubiuser/snapclient-docker)

## Getting started

Images for `amd64` can be found at [ghcr.io/yubiuser/librespot-shairport-snapserver](ghcr.io/yubiuser/librespot-shairport-snapserver).

Use with

```plain
docker pull ghcr.io/yubiuser/librespot-shairport-snapserver
docker run -d --rm --net host -v ./snapserver.conf:/etc/snapserver.conf --name snapserver librespot-shairport-snapserver
```

or with `docker-compose.yml`

```yml
services:
  snapcast:
    image: ghcr.io/yubiuser/librespot-shairport-snapserver
    container_name: snapcast
    restart: unless-stopped
    network_mode: host
    volumes:
     - ./snapserver.conf:/etc/snapserver.conf
     #- /tmp/snapfifo:/tmp/snapfifo
```

### Build locally

To build the image simply run

`docker build -t librespot-shairport-snapserver:local -f ./alpine.dockerfile .`

## Notes

- Based on Alpine 3:20; final image size is ~116MB
- All `(c)make` calles use the option `-j $(( $(nproc) -1 ))` to leave one CPU for normal operation
- `s6-overlay` is used as `init` system (same as the [shairport-sync docker image](https://github.com/mikebrady/shairport-sync/tree/master/docker)). This is necessary, because *shairport-sync* needs a companion application called [NQPTP](https://github.com/mikebrady/nqptp) which needs to be started from `root` to run as deamon.
  - `s6-rc` with configured dependencies is used to start all services. `snapserver` should start as last
  - `s6-notifyoncheck` is used to check readiness of the started services `dbus` and `avahi`. The actual check is performed by sending `dbus`messages and analyzing the reply.
- Adjust `snapserver.conf` as required (Airplay 2 needs port 7000)
- [Snapweb](https://github.com/badaix/snapweb) is included in the image and can be accessed on `http://<snapserver host>:1780`
