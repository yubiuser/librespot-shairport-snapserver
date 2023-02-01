# librespot-shairport-snapserver

Alpine based Docker image for running the [snapserver part of snapcast](https://github.com/badaix/snapcast) with
[librespot](https://github.com/librespot-org/librespot) and [shairport-sync](https://github.com/mikebrady/shairport-sync) as input.

Idea adapted from [librespot-snapserver](https://github.com/djmaze/librespot-snapserver) and based on [shairport-sync docker image](https://github.com/mikebrady/shairport-sync/tree/master/docker)

 **Background:** As of 01/2023 the last release of *snapcast* is v0.26 from 12/2022 which is missing 118 commits compared to `develop`.
 Same for *librespot*, last release is v0.46 from 07/2022 which is missing 266 commits compared to `dev`.
 Therefore, everything is compiled from source.

 **Note:** Current last commit of the development branches for all repos are used to compile the lastest versions.

## Getting started

Images for `amd64` can be found at [ghcr.io/yubiuser/librespot-shairport-snapserver](ghcr.io/yubiuser/librespot-shairport-snapserver).

Use with

```plain
docker pull ghcr.io/yubiuser/librespot-shairport-snapserver:1.0.0
docker run -d --rm --net host --name snapserver librespot-shairport-snapserver:1.0.0
```

### Build locally

To build the image simply run

`docker build -t librespot-shairport-snapserver:local -f ./alpine.dockerfile .`

Start the container with

`docker run -d --rm --net host --name librespot-shairport-snapserver librespot-shairport-snapserver:local`

## Notes

- Based on current Alpine version 3:17
- Final image size is ~175 MB
- All `make` calles use the option `-j $(( $(nproc) -1 ))` to leave one CPU for normal operation
- Compiling `snapserver`
  - A deprecated option needs to be removed on the `airplay-stream.cpp`
  - The compiler flag `HAS_EXPAT=1` needs to be set
- `s6-overlay` is used as `init` system (same as the [shairport-sync docker image](https://github.com/mikebrady/shairport-sync/tree/master/docker)). This is necessary, because *shairport-sync* needs a companion application called [NQPTP](https://github.com/mikebrady/nqptp) which needs to be run as `root` as deamon.
  - The `ENTRYPOINT ["/init"]` is set within the [docker-alpine-s6 base image](https://github.com/crazy-max/docker-alpine-s6) already
  - `s6-rc` with configured dependencies is used to start all services. `snapserver` should start as last
  - `s6-rc` considers *longrun* services as "started" when the `run` file is executed. However, some services need a bit time to fully startup. To not breake dependent services, they check for existence of `*.pid` files of previous services
- Adjust `snapserver.conf` as required (Airplay 2 needs port 7000)
- [Snapweb](https://github.com/badaix/snapweb) is inclued in the image and can be accessed on `http://<snapserver host>:1780`
- `hop`  is included for debugging purposes
- `shairport-sync-metadata-reader ` is inclued for debuging purposes
- I tried to provide multi-arch images as well, however, cross-compiling/building on Github with `QEMU` and `buildx` took hours and was canceled a few times automatically. I tried with a Debian based images as well, but no avail. The `debian.dockerfile` should provide a usable image with only minor necesary changes to the `s6` files. Debian images are ~307 MB.
