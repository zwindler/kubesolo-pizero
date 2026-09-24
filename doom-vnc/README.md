# doom-vnc

DOOM ([doomgeneric](https://github.com/ozkl/doomgeneric)) with a [LibVNCServer](https://github.com/LibVNC/libvncserver) backend: the game serves its own framebuffer over VNC. No X server, no SDL, one static binary.

- 320x200, native resolution: let the VNC client scale it (macOS Screen Sharing, RealVNC Viewer, Remmina...)
- the game is paused while no client is connected (0 % CPU)
- `FROM scratch` image: the 1.1 MB static binary and `doom1.wad` (shareware v1.9, MD5 checked at build time)

## Run

```sh
docker run --rm -p 5900:5900 -e VNC_PASSWORD=idbehold ghcr.io/zwindler/kubesolo-pizero/doom-vnc:latest
```

Then open `vnc://localhost:5900`. Without `VNC_PASSWORD`, no authentication is required.

| Variable | Default | |
|---|---|---|
| `VNC_PASSWORD` | none | VNC password |
| `VNC_PORT` | `5900` | listening port |

The game writes its config and saves in the working directory: mount something writable there when running with a read-only root filesystem (see [`../demo/manifests/doom.yaml`](../demo/manifests/doom.yaml)).

## Keys

Arrows move, Ctrl fires, Space opens doors, Shift runs, Alt strafes, Enter/Escape for menus, Tab for the map.

## Build

```sh
docker buildx build --platform linux/arm64 -t doom-vnc:arm64 --load .
```

`RESX`/`RESY` build args change the framebuffer size (doomgeneric scales by an integer factor, e.g. 640x400), at the cost of 4x more pixels to encode.
