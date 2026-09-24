# kubesolo-pizero

Kubernetes on a Raspberry Pi Zero 2 W (512 MB of RAM, 416 MiB visible out of the box), with [KubeSolo](https://github.com/portainer/kubesolo), and yes, it runs DOOM.

- [`demo/`](demo/): scripts and manifests for a live demo, from a freshly flashed Raspberry Pi OS Lite to DOOM in a pod
- [`doom-vnc/`](doom-vnc/): DOOM that serves its own screen over VNC, in a 2.4 MB image

## Results

Measured on a Pi Zero 2 W, Raspberry Pi OS Lite (Debian 13 trixie, kernel 6.18), KubeSolo v1.2.0 (Kubernetes 1.35), September 2026.

### OS tuning

`free -m` after boot, one SSH session, no workload. The first rows come from the first version of this experiment (V1, older image and kernel, hence 464 vs 462 MiB visible), the others were measured for this repository.

| Step | Visible | Used | Available | Source |
|---|---|---|---|---|
| Stock Raspberry Pi OS Lite (`gpu_mem` 64 MiB) | 416 MiB | 142 MiB | | V1 |
| `gpu_mem=16` (headless, minimum value) | **464 MiB (+48)** | | | V1 |
| avahi, polkit, ModemManager, bluetooth disabled | | -10 to -12 MiB | | V1 |
| audio, camera/display detection, KMS and bluetooth off in `config.txt`, avahi/bluez purged, gettys masked, apt/man-db timers and cloud-init disabled | 462 MiB | 130 MiB | 332 MiB | measured |
| `vm.min_free_kbytes` 16384 to 8192 | | | +25 MiB | measured, mostly watermark accounting (~8 MiB real) |
| zram without SD writeback, `swappiness=100`, `page-cluster=0` | | | +5 MiB | measured, boot 34 s to 28 s |
| camera/codec/DRM modules blacklisted, cron disabled | | | +2 MiB | measured |
| no `pam_systemd`, no logind | | | +9 MiB | measured, no `systemd --user` per login |
| NetworkManager replaced by wpa_supplicant + dhcpcd | | | +5 MiB | measured, system.slice -19 MiB, **boot 27 s to 13 s** |
| **Result** | **462 MiB** | **86 MiB** | **376 MiB** | |

The memory cgroup (`cgroup_enable=memory`) is not a gain but a requirement: the Zero 2 W device tree disables it and no pod can start without it.

### KubeSolo

| Setting | MemAvailable with KubeSolo + CoreDNS | Idle CPU |
|---|---|---|
| default (with local-path-provisioner) | 118 MiB | |
| `--no-local-storage` | 133 MiB | 11 % |
| + `GOMEMLIMIT=180MiB` | **182 MiB** | 12-15 % |
| + `GOMEMLIMIT=160MiB` | 197 MiB | 65-79 %, GC thrashing, not usable |

### DOOM

| | [storax/kubedoom](https://github.com/storax/kubedoom) | [doom-vnc](doom-vnc/) |
|---|---|---|
| Compressed image | 126 MB | **2.4 MB** |
| Start at every boot | 4 min 38 s pull | **seconds** |
| RAM, no client | ~32 MiB (38 peak) | **2.5 MiB** |
| CPU, no client | 45-50 % | **0 %** (paused) |
| RAM, playing | | ~4 MiB (6 MiB peak) |
| Playing over ZRLE | | 26 fps, 0.33 MB/s, 58 % of one core |

## Known KubeSolo v1.2.0 issues worked around here

- The installer renders boolean options as `--flag=false`, rejected by the binary (fixed on `develop`, [#188](https://github.com/portainer/kubesolo/pull/188)): `ExecStart` is overridden with `--no-local-storage`.
- KubeSolo never stops by itself on SIGTERM (kubelet and controller-manager keep running) and leaves pods orphaned: `TimeoutStopSec=30` and `ExecStopPost=systemctl --no-block stop kubepods.slice`.
- Every start wipes the containerd content store and snapshots ([#197](https://github.com/portainer/kubesolo/issues/197)): images come back from a registry at each boot, hence the small images.
- On the SD card, unpacking the 64 MB local-path-provisioner layer (16,691 files) takes 5+ minutes, longer than the kubelet 2 min runtime timeout: local storage is disabled.

## License

GPL-2.0 (doom-vnc builds on [doomgeneric](https://github.com/ozkl/doomgeneric)). `doom-vnc/doom1.wad` is the DOOM v1.9 shareware episode by id Software, redistributed unmodified under its shareware terms.
