# Live demo

From a freshly flashed Raspberry Pi OS Lite to DOOM in a Kubernetes pod, on a Raspberry Pi Zero 2 W.

## Before the talk

1. Flash **Raspberry Pi OS Lite (64-bit, trixie)** with Raspberry Pi Imager: hostname, user, SSH, wifi of the venue (or a phone hotspot).
2. Boot, copy this repository to the Pi, then fetch everything the demo needs (network required, ~210 MB):

   ```sh
   sudo ./demo/00-prefetch.sh
   ```

   Files land in `/opt/kubesolo-demo`: KubeSolo offline build (all images embedded) and installer, the `iptables`/`dropbear` packages, `ctr` and `crane`, and the nginx and DOOM images as archives, all checksum-verified. If the hotspot has no Internet access, run `sudo ./demo/import-images.sh` after step 7 below.

3. Optional but recommended: rehearse once, then reflash and redo steps 1-2.

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

The memory cgroup (`boot` step) is mandatory: without it KubeSolo installs fine but no pod can start (`memory.max: no such file or directory`).

## Backup Pi

Run the whole demo once, then `sudo ./demo/import-images.sh --install`: KubeSolo wipes its images at every start (upstream [#197](https://github.com/portainer/kubesolo/issues/197)), this re-imports nginx and DOOM after each KubeSolo start, once the kubelet is up (importing earlier races with KubeSolo's own startup import and makes it exit). From power-on to the three pods running: ~4.5 min.

## Notes

- `network` rewrites the wifi setup from the Imager netplan file (Raspberry Pi OS uses netplan with the NetworkManager renderer, and there is no systemd-resolved: dhcpcd writes `/etc/resolv.conf`). It requests the same IPv4 address. **Run `confirm` within 10 minutes after the reboot**, otherwise the Pi restores NetworkManager and reboots.
- `ssh` (Dropbear instead of OpenSSH) is not part of `all`: it only saves ~3 MiB and adds one more thing that can go wrong on stage.
- After `sessions`, reboot with `./demo/10-os-tuning.sh reboot`: `systemctl reboot` complains about logind before falling back.
- KubeSolo wipes its images at every start (upstream [#197](https://github.com/portainer/kubesolo/issues/197)): after a reboot, nginx and DOOM are pulled again (a few seconds each), or re-imported (see Backup Pi).
- Scale the VNC window on the client side for the projector, the game renders 320x200.
