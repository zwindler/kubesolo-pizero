#!/usr/bin/env bash
# OS tuning for KubeSolo on a Raspberry Pi Zero 2 W (Raspberry Pi OS Lite, trixie).
# Every step is idempotent and can be run on its own during a live demo.
set -euo pipefail

DEMO_DIR=/opt/kubesolo-demo
STATE_DIR=/etc/kubesolo-demo
CONFIG=/boot/firmware/config.txt
CMDLINE=/boot/firmware/cmdline.txt

usage() {
  cat <<EOF
usage: sudo $0 <step> [<step>...]

live steps (no reboot):
  services   stop and disable services useless on a headless node
  sessions   no per-login systemd user manager, no logind
  memory     sysctl, zram without SD writeback, small volatile journal

reboot steps (apply, then: sudo $0 reboot):
  boot       config.txt (gpu_mem=16, no audio/camera/display/bt/kms), cmdline (memory cgroup), module blacklist
  network    replace NetworkManager with wpa_supplicant + dhcpcd (auto rollback after 10 min)
  ssh        replace OpenSSH with Dropbear (optional, auto rollback after 10 min)

helpers:
  show       memory, top processes, boot time
  confirm    after the reboot: keep network/ssh changes (cancels the rollback)
  reboot     reboot without logind
  live       services sessions memory
  all        services sessions memory boot network
EOF
}

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
unit_exists() { systemctl list-unit-files --no-legend "$1" 2>/dev/null | grep -q .; }
mem_available() { awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo; }

step_show() {
  free -m
  echo "MemAvailable: $(mem_available) MiB"
  ps -eo rss,comm --sort=-rss | awk 'NR==1{print "   RSS COMMAND"; next} NR<=12{printf "%6.1fM %s\n", $1/1024, $2}'
  systemd-analyze 2>/dev/null | head -1 || true
}

step_services() {
  log "services"
  local u
  for u in avahi-daemon.service avahi-daemon.socket bluetooth.service hciuart.service ModemManager.service \
           cron.service udisks2.service apt-daily.timer apt-daily-upgrade.timer apt-listchanges.timer \
           dpkg-db-backup.timer e2scrub_all.timer logrotate.timer man-db.timer; do
    if unit_exists "$u" && systemctl disable --now "$u" >/dev/null 2>&1; then echo "disabled $u"; fi
  done
  for u in getty@tty1.service serial-getty@ttyAMA0.service; do
    if systemctl mask --now "$u" >/dev/null 2>&1; then echo "masked $u"; fi
  done
  mkdir -p /etc/cloud && touch /etc/cloud/cloud-init.disabled && echo "disabled cloud-init"
}

step_sessions() {
  log "sessions"
  DEBIAN_FRONTEND=noninteractive pam-auth-update --disable systemd
  echo "pam_systemd removed: no systemd --user / sd-pam per SSH login (next logins)"
  systemctl mask systemd-logind.service >/dev/null 2>&1
  systemctl stop systemd-logind.service 2>/dev/null || true
  echo "systemd-logind masked (use '$0 reboot' from now on)"
}

step_memory() {
  log "memory"
  cat > /etc/sysctl.d/99-zz-kubesolo-demo.conf <<EOF
vm.min_free_kbytes = 8192
vm.swappiness = 100
vm.page-cluster = 0
EOF
  /usr/sbin/sysctl -q --system
  echo "min_free_kbytes=$(cat /proc/sys/vm/min_free_kbytes) swappiness=$(cat /proc/sys/vm/swappiness) page-cluster=$(cat /proc/sys/vm/page-cluster)"

  mkdir -p /etc/rpi/swap.conf.d
  printf '[Main]\nMechanism=zram\n' > /etc/rpi/swap.conf.d/10-kubesolo-demo.conf
  echo "zram only, no writeback to the SD card (next boot)"

  mkdir -p /etc/systemd/journald.conf.d
  printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=4M\n' > /etc/systemd/journald.conf.d/10-kubesolo-demo.conf
  systemctl restart systemd-journald
  echo "journal in RAM, capped to 4M"
}

append_all() {
  if [ "$(grep '^\[' "$CONFIG" | tail -1)" != "[all]" ] && grep -q '^\[' "$CONFIG"; then
    printf '\n[all]\n' >> "$CONFIG"
  fi
  echo "$1" >> "$CONFIG"
}

set_config() {
  local key=$1 value=$2
  if grep -q "^${key}=" "$CONFIG"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG"
  else
    append_all "${key}=${value}"
  fi
}

step_boot() {
  log "boot"
  cp -n "$CONFIG" "$CONFIG.orig"
  cp -n "$CMDLINE" "$CMDLINE.orig"
  set_config gpu_mem 16
  set_config dtparam=audio off
  set_config camera_auto_detect 0
  set_config display_auto_detect 0
  set_config max_framebuffers 1
  sed -i 's|^dtoverlay=vc4-kms-v3d|#dtoverlay=vc4-kms-v3d|' "$CONFIG"
  grep -q '^dtoverlay=disable-bt' "$CONFIG" || append_all dtoverlay=disable-bt
  echo "config.txt: $(grep -E '^(gpu_mem|dtparam=audio|camera_auto_detect|display_auto_detect|max_framebuffers|dtoverlay=disable-bt)' "$CONFIG" | tr '\n' ' ')"

  # The Zero 2 W device tree injects cgroup_disable=memory; a later cgroup_enable wins.
  grep -q 'cgroup_enable=memory' "$CMDLINE" || sed -i '1 s|^|cgroup_enable=memory |' "$CMDLINE"
  grep -q 'apparmor=0' "$CMDLINE" || sed -i '1 s|$| apparmor=0|' "$CMDLINE"
  echo "cmdline.txt: $(cat "$CMDLINE")"

  printf 'blacklist %s\n' snd_bcm2835 bcm2835_codec bcm2835_isp bcm2835_v4l2 bcm2835_mmal_vchiq vc_sm_cma drm \
    > /etc/modprobe.d/kubesolo-demo-blacklist.conf
  echo "camera/codec/drm/sound modules blacklisted"
}

install_rescue() {
  cat > /usr/local/sbin/kubesolo-demo-rescue <<'EOF'
#!/bin/sh
sleep 600
[ -f /run/kubesolo-demo-ok ] && exit 0
if [ -f /etc/kubesolo-demo/network.applied ]; then
  mv /root/netplan-nm-backup/*.yaml /etc/netplan/ 2>/dev/null
  systemctl disable wpa_supplicant@wlan0.service dhcpcd-wlan0.service
  systemctl enable NetworkManager.service NetworkManager-wait-online.service NetworkManager-dispatcher.service wpa_supplicant.service
  rm -f /etc/kubesolo-demo/network.applied
fi
if [ -f /etc/kubesolo-demo/ssh.applied ]; then
  systemctl disable dropbear-lite.service
  systemctl enable ssh.service
  rm -f /etc/kubesolo-demo/ssh.applied
fi
systemctl disable kubesolo-demo-rescue.service
systemctl start reboot.target
EOF
  chmod 755 /usr/local/sbin/kubesolo-demo-rescue
  cat > /etc/systemd/system/kubesolo-demo-rescue.service <<'EOF'
[Unit]
Description=Roll back network/ssh demo changes unless confirmed

[Service]
ExecStart=/usr/local/sbin/kubesolo-demo-rescue

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable kubesolo-demo-rescue.service >/dev/null 2>&1
}

step_network() {
  log "network"
  if systemctl is-enabled -q dhcpcd-wlan0.service 2>/dev/null; then
    echo "already using wpa_supplicant + dhcpcd"
    return
  fi
  local nm_yaml ip
  nm_yaml=$(grep -l 'wifis:' /etc/netplan/*.yaml 2>/dev/null | head -1 || true)
  [ -n "$nm_yaml" ] || { echo "no netplan wifi config found, skipping"; return 1; }
  ip=$(ip -4 -o addr show wlan0 | awk '{print $4}' | cut -d/ -f1 | head -1)

  python3 - "$nm_yaml" <<'PY'
import re, subprocess, sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
ssid, ap = next(iter(d["network"]["wifis"]["wlan0"]["access-points"].items()))
pw = ap["auth"].get("password") or ap["auth"]["key"]
if re.fullmatch(r"[0-9a-fA-F]{64}", pw):
    psk = pw
else:
    r = subprocess.run(["wpa_passphrase", ssid, pw], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("wpa_passphrase failed")
    psk = re.search(r"^\s*psk=([0-9a-f]{64})$", r.stdout, re.M).group(1)
with open("/etc/wpa_supplicant/wpa_supplicant-wlan0.conf", "w") as f:
    f.write("ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev\nupdate_config=0\ncountry=FR\n\n"
            "network={\n\tssid=\"%s\"\n\tpsk=%s\n}\n" % (ssid, psk))
PY
  chmod 600 /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

  cp -n /etc/dhcpcd.conf /etc/dhcpcd.conf.orig
  cat > /etc/dhcpcd.conf <<EOF
allowinterfaces wlan0
hostname
clientid
persistent
option domain_name_servers, domain_name, domain_search
option classless_static_routes
option interface_mtu
option ntp_servers
require dhcp_server_identifier
slaac hwaddr
interface wlan0
${ip:+request $ip}
EOF

  cat > /etc/systemd/system/dhcpcd-wlan0.service <<'EOF'
[Unit]
Description=dhcpcd on wlan0
BindsTo=sys-subsystem-net-devices-wlan0.device
After=sys-subsystem-net-devices-wlan0.device wpa_supplicant@wlan0.service
Wants=network.target
Before=network.target

[Service]
ExecStart=/usr/sbin/dhcpcd -B -q wlan0
Restart=always

[Install]
WantedBy=multi-user.target
EOF

  mkdir -p /root/netplan-nm-backup "$STATE_DIR"
  mv /etc/netplan/90-NM-*.yaml /root/netplan-nm-backup/ 2>/dev/null || true
  touch "$STATE_DIR/network.applied"
  install_rescue
  systemctl enable wpa_supplicant@wlan0.service dhcpcd-wlan0.service >/dev/null 2>&1
  systemctl disable NetworkManager.service NetworkManager-wait-online.service NetworkManager-dispatcher.service wpa_supplicant.service >/dev/null 2>&1
  echo "NetworkManager disabled (still installed), wlan0 via wpa_supplicant + dhcpcd${ip:+, requesting $ip}"
  echo "after the reboot, run '$0 confirm' within 10 minutes or it rolls back"
}

step_ssh() {
  log "ssh"
  if ! command -v dropbear >/dev/null; then
    dpkg -i "$DEMO_DIR"/debs/libtommath1_*.deb "$DEMO_DIR"/debs/libtomcrypt1_*.deb "$DEMO_DIR"/debs/dropbear-bin_*.deb >/dev/null
  fi
  mkdir -p /etc/dropbear "$STATE_DIR"
  local t
  for t in ed25519 ecdsa rsa; do
    if [ -f "/etc/ssh/ssh_host_${t}_key" ] && [ ! -f "/etc/dropbear/dropbear_${t}_host_key" ]; then
      dropbearconvert openssh dropbear "/etc/ssh/ssh_host_${t}_key" "/etc/dropbear/dropbear_${t}_host_key" >/dev/null 2>&1
    fi
  done
  cat > /etc/systemd/system/dropbear-lite.service <<'EOF'
[Unit]
Description=Dropbear SSH server
After=network.target

[Service]
ExecStart=/usr/sbin/dropbear -F -E -w -p 22 -r /etc/dropbear/dropbear_ed25519_host_key -r /etc/dropbear/dropbear_ecdsa_host_key -r /etc/dropbear/dropbear_rsa_host_key
Restart=always
OOMScoreAdjust=-1000

[Install]
WantedBy=multi-user.target
EOF
  touch "$STATE_DIR/ssh.applied"
  install_rescue
  systemctl enable dropbear-lite.service >/dev/null 2>&1
  systemctl disable ssh.service ssh.socket >/dev/null 2>&1 || true
  echo "Dropbear on port 22 from next boot (same host keys), OpenSSH disabled but installed"
  echo "after the reboot, run '$0 confirm' within 10 minutes or it rolls back"
}

step_confirm() {
  touch /run/kubesolo-demo-ok
  systemctl disable kubesolo-demo-rescue.service >/dev/null 2>&1 || true
  echo "network/ssh changes confirmed, rollback cancelled"
}

step_reboot() { sync; systemctl start reboot.target; }

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
[ $# -gt 0 ] || { usage; exit 1; }

steps=()
for arg in "$@"; do
  case "$arg" in
    live) steps+=(services sessions memory) ;;
    all)  steps+=(services sessions memory boot network) ;;
    *)    steps+=("$arg") ;;
  esac
done

before=$(mem_available)
for step in "${steps[@]}"; do
  case "$step" in
    show|services|sessions|memory|boot|network|ssh|confirm|reboot) "step_$step" ;;
    *) usage; exit 1 ;;
  esac
done
case " ${steps[*]} " in
  *" show "*|*" reboot "*) ;;
  *) printf '\nMemAvailable: %s MiB -> %s MiB\n' "$before" "$(mem_available)" ;;
esac
