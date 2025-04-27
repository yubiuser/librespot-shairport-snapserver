# librespot-shairport-snapserver

Alpine-based Docker image for running the **snapserver** part of [snapcast](https://github.com/badaix/snapcast) with  
[**librespot**](https://github.com/librespot-org/librespot) and [**shairport-sync**](https://github.com/mikebrady/shairport-sync) as inputs.

Idea adapted from [librespot-snapserver](https://github.com/djmaze/librespot-snapserver) and based on the  
[shairport-sync Docker image](https://github.com/mikebrady/shairport-sync/tree/master/docker).

**Background:** When this project started, the latest releases of *snapcast* and *librespot* were behind their  
 respective `develop` branches. Therefore, everything is compiled from source using specific tested commits from the development branches.

> **Note:** The corresponding Docker image for running `snapclient` can be found here:  
> [yubiuser/snapclient-docker](https://github.com/yubiuser/snapclient-docker)

---

## Docker Images

Multi-arch Docker images (`linux/amd64`, `linux/arm64`) for `librespot`, `shairport-sync`, and `snapserver` are published to the [GitHub Container Registry (GHCR)](https://github.com/yubiuser?tab=packages&repo_name=librespot-shairport-snapserver). Docker will automatically pull the correct architecture.

---

### Development Image Variants

These images are built from the **`development`** branch. They contain the latest ongoing changes and may not be stable.  

> **Note:** For stable releases follow the instructions on [master](https://github.com/yubiuser/librespot-shairport-snapserver/tree/master) branch. Pushing to `master` or creating a release produces tags like `latest`, `latest-slim`, `vX.Y.Z`, and `vX.Y.Z-slim`.
>
#### 1. Full Development Version (`development`)

- Represents the latest development state of the **full-featured** image.  
- Contains `snapserver`, `librespot`, `shairport-sync` **plus** a full Python installation and dependencies.  
- **Tag:** `development`  
- **Pull:**  

  ```bash
  docker pull ghcr.io/yubiuser/librespot-shairport-snapserver:development
  ```

#### 2. Slim Development Version (`development-slim`)

- Represents the latest development state of the **minimal** image.  
- Contains `snapserver`, `librespot`, and `shairport-sync` but **excludes** Python and related tools.  
- **Tag:** `development-slim`  
- **Pull:**  

  ```bash
  docker pull ghcr.io/yubiuser/librespot-shairport-snapserver:development-slim
  ```

---

## Usage Examples

### Using the Full Development Image

```bash
docker pull ghcr.io/yubiuser/librespot-shairport-snapserver:development
docker run -d --rm --net host   -v ./snapserver.conf:/etc/snapserver.conf   --name snapserver ghcr.io/yubiuser/librespot-shairport-snapserver:development
```

### Using with docker-compose

```yml
services:
  snapcast:
    image: ghcr.io/yubiuser/librespot-shairport-snapserver:development
    # or slim version:
    # image: ghcr.io/yubiuser/librespot-shairport-snapserver:development-slim
    container_name: snapcast
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./snapserver.conf:/etc/snapserver.conf
      # Example FIFO mapping if needed
      # - /tmp/snapfifo:/tmp/snapfifo
```

> Replace `./snapserver.conf` with the path to your actual Snapserver config file.

---

## Building Locally

To build the image locally simply run:

```bash
docker build -t librespot-shairport-snapserver:local -f ./alpine.dockerfile .
```

---

## Notes

- Based on Alpine 3.21; final image size is ~200 MB (full version); ~120 MB (slim version).  
- All CMake builds use `-j $(( $(nproc) - 1 ))` to leave one CPU free for normal operation.  
- Uses [s6-overlay](https://github.com/just-containers/s6-overlay) as `init` system:  
  - Required by [NQPTP](https://github.com/mikebrady/nqptp) companion for shairport-sync.  
  - Services launched via `s6-rc` with proper dependencies (snapserver starts last).  
  - Uses `s6-notifyoncheck` to wait on `dbus` and `avahi` readiness. The actual check is performed by sending `dbus`messages and analyzing the reply.
- Adjust `snapserver.conf` as needed (AirPlay 2 uses port 7000).  
- [Snapweb](https://github.com/badaix/snapweb) is included and available at `http://<snapserver-host>:1780`.  
