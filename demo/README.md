# Live demo

From a freshly flashed Raspberry Pi OS Lite to DOOM in a Kubernetes pod, on a Raspberry Pi Zero 2 W.

## Before the talk

1. Flash **Raspberry Pi OS Lite (64-bit, trixie)** with Raspberry Pi Imager: hostname, user, SSH, wifi of the venue (or a phone hotspot).
2. Boot, copy this repository to the Pi, then fetch everything the demo needs (network required, ~210 MB):

   ```sh
   sudo ./demo/00-prefetch.sh
   ```

   Files land in `/opt/kubesolo-demo`: KubeSolo offline build (all images embedded) and installer, the `iptables` packages, `ctr` and `crane`, and the nginx and DOOM images as archives, all checksum-verified. If the hotspot has no Internet access, run `sudo ./demo/import-images.sh` after step 7 below. It also gives the user passwordless sudo, which the [scripted demo](#scripted-demo) needs: Imager no longer sets it up.

3. Imager takes a single wifi network. To add another one, typically a phone hotspot when Imager got the home wifi: `sudo ./demo/10-os-tuning.sh wifi-add <ssid>` (asks for the passphrase, keeps only the derived PSK). It is preferred over the Imager network once the `network` step has run.
4. Optional but recommended: rehearse once, then reflash and redo steps 1-3.

## On stage

Run on the Pi (`sudo`), `kubectl` runs on the laptop.

| # | Command | Shows | Time |
|---|---|---|---|
| 1 | `./demo/10-os-tuning.sh show` | the stock image: 416 MiB visible (64 MiB for the GPU), ~270 MiB available | |
| 2 | `./demo/10-os-tuning.sh services` | headless node: no avahi, bluetooth, cron, timers, getty | seconds |
| 3 | `./demo/10-os-tuning.sh sessions` | no `systemd --user` per login, no logind | seconds |
| 4 | `./demo/10-os-tuning.sh memory wifi` | `min_free_kbytes`, zram tuning, journal in RAM; wifi power save off (ping 104 ms avg / 1.3 s max to 8 ms / 13 ms) | seconds |
| 5 | `./demo/10-os-tuning.sh boot network` then `./demo/10-os-tuning.sh reboot` | `gpu_mem=16`, memory cgroup, modules; NetworkManager replaced | ~15 s boot |
| 6 | `./demo/10-os-tuning.sh confirm show` | keep the network change: 462 MiB visible, ~376 MiB available, 13 s boot | |
| 7 | `./demo/20-kubesolo.sh` | KubeSolo installed offline, first start | ~3 min |
| 8 | `./demo/fetch-kubeconfig.sh <user>@<pi>` then `kubectl get nodes,pods -A` | a Kubernetes node on a Pi Zero | |
| 9 | `kubectl apply -f demo/manifests/nginx.yaml` then `curl http://<pi>:30080` | a real workload | ~1 min (pull) |
| 10 | `kubectl apply -f demo/manifests/doom.yaml` then `vnc://<pi>:30900` (password `idbehold`) | it runs DOOM | seconds |
| 11 | `kubectl apply -f demo/manifests/doom-grid.yaml` then `kubectl -n doom scale deploy/doom-grid --replicas=9` | can we scale DOOM? 9 games, one VNC window each | ~2 min |

## Scripted demo

[`talk/`](talk/) runs every step above from the laptop with [demo-magic](https://github.com/paxtonhare/demo-magic): each command is typed on screen, then run locally (`kubectl`, `ping`, `curl`, TigerVNC) or on the Pi over a single shared SSH connection. Requires `pv`, `fzf` and TigerVNC.

```sh
PI_HOST=<user>@<pi> ./demo/talk/menu.sh
```

Settings can also come from a file: `DEMO_ENV=<file>` (`PI_HOST`, `VIDEO_DIR` for fallback videos named `01.mp4`...`11.mp4`, `VNC_PASSWORD`). In any demo, `v` instead of Enter plays the fallback video.

The memory cgroup (`boot` step) is mandatory: without it KubeSolo installs fine but no pod can start (`memory.max: no such file or directory`).

## Backup Pi

Run the whole demo once. Since KubeSolo v1.2.1 the images and the pods survive restarts: a KubeSolo restart takes ~95 s and keeps the same pods. Power the backup Pi from its own supply: a laptop or dock USB port can drop when the laptop reboots.

## Notes

- `network` rewrites the wifi setup from the Imager netplan file (Raspberry Pi OS uses netplan with the NetworkManager renderer, and there is no systemd-resolved: dhcpcd writes `/etc/resolv.conf`). It requests the same IPv4 address. **Run `confirm` within 10 minutes after the reboot**, otherwise the Pi restores NetworkManager and reboots.
- After `sessions`, reboot with `./demo/10-os-tuning.sh reboot`: `systemctl reboot` complains about logind before falling back.
- If the hotspot has no Internet access, `sudo ./demo/import-images.sh` imports nginx and DOOM from the archives fetched by `00-prefetch.sh`.
- DOOM serves 640x400 (`VNC_SCALE=2` in `doom.yaml`) for VNC clients that cannot scale, such as TigerVNC. `doom-grid.yaml` stays at 320x200 so that 9 windows fit on one screen.
