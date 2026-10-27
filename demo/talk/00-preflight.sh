#!/usr/bin/env bash
# Demo 0 - preflight before the talk: laptop, then finds the demo and backup
# Pis on the hotspot and checks both. Read-only on the Pis; only fetches the
# backup kubeconfig and, after confirmation, runs ssh-keygen -R.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -n "${DEMO_ENV:-}" && -f "$DEMO_ENV" ]]; then
  . "$DEMO_ENV"
fi
if [[ "${PI_HOST:-}" == *@* ]]; then
  PI_USER="${PI_USER:-${PI_HOST%@*}}"
else
  PI_USER="${PI_USER:-$USER}"
fi
DEMO_HOSTNAME="${DEMO_HOSTNAME:-kubedoom-demo}"
BACKUP_HOSTNAME="${BACKUP_HOSTNAME:-kubedoom-backup}"
HOTSPOT_SSID="${HOTSPOT_SSID:-kubesolo}"
IFACE="${IFACE:-en0}"
PI_OUIS="${PI_OUIS:-28:cd:c1 2c:cf:67 88:a2:9e b8:27:eb d8:3a:dd dc:a6:32 e4:5f:01}"
VNCVIEWER="${VNCVIEWER:-/Applications/TigerVNC.app/Contents/MacOS/vncviewer}"
BACKUP_KUBECONFIG="${BACKUP_KUBECONFIG:-$REPO_DIR/kubeconfig-backup}"

SSH=(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)

RED=$'\033[0;31m' GREEN=$'\033[0;32m' BROWN=$'\033[0;33m' PURPLE=$'\033[0;35m' RESET=$'\033[0m'
FAILS=0
ok()    { echo "  ${GREEN}ok${RESET}    $*"; }
warn()  { echo "  ${BROWN}warn${RESET}  $*"; }
ko()    { echo "  ${RED}KO${RESET}    $*"; FAILS=$((FAILS + 1)); }
fix()   { ko "$1: $2"; [[ -n "$NEXT" ]] || NEXT="$2"; }
next()  { [[ -z "$NEXT" ]] || echo "  ${BROWN}next${RESET}  $NEXT"; NEXT=""; }
NEXT=""
title() { echo; echo "${PURPLE}== $*${RESET}"; }

scripts_hash_local() {
  (cd "$REPO_DIR" && find demo -maxdepth 1 -name '*.sh' | LC_ALL=C sort | xargs md5 -r | awk '{print $1, $2}' | md5 -q)
}

title "Laptop"
for tool in fzf pv kubectl; do
  if command -v "$tool" >/dev/null; then ok "$tool"; else ko "$tool missing: brew install $tool"; fi
done
if [[ -x "$VNCVIEWER" ]]; then ok "TigerVNC"; else ko "TigerVNC missing ($VNCVIEWER)"; fi
if command -v warp-cli >/dev/null && warp-cli status 2>/dev/null | grep -q "Status update: Connected"; then
  ko "WARP connected: warp-cli disconnect"
else
  ok "WARP disconnected"
fi
if [[ -n "${VIDEO_DIR:-}" ]]; then
  missing=""
  for i in 01 02 03 04 05 06 07 08 09 10 11; do
    [[ -f "$VIDEO_DIR/$i.mp4" ]] || missing="$missing $i"
  done
  if [[ -z "$missing" ]]; then ok "fallback videos in $VIDEO_DIR"; else warn "fallback videos missing:$missing"; fi
else
  warn "VIDEO_DIR not set: no fallback videos (v key)"
fi

mac_ip=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
if [[ -z "$mac_ip" ]]; then
  ko "no IPv4 address on $IFACE: join the hotspot first"
  exit 1
fi
# Phone hotspots hand out a /24
prefix="${mac_ip%.*}"
route_if=$(route -n get "$prefix.1" 2>/dev/null | awk '/interface:/{print $2}')
if [[ "$route_if" == "$IFACE" ]]; then
  ok "laptop $mac_ip, $prefix.0/24 routed through $IFACE"
else
  ko "$prefix.0/24 routed through ${route_if:-nothing}, not $IFACE: VPN still up?"
fi

title "Pis on $prefix.0/24"
alive=$(for i in $(seq 1 254); do
  (ping -c1 -t1 "$prefix.$i" >/dev/null 2>&1 && echo "$prefix.$i") &
done; wait)
# macOS arp drops leading zeros (e4:5f:1:...) and keeps stale entries
candidates=$(arp -an -i "$IFACE" | awk -v ouis="$PI_OUIS" '
  BEGIN { n = split(ouis, o, " "); for (i = 1; i <= n; i++) want[o[i]] = 1 }
  $4 ~ /:/ {
    split(tolower($4), b, ":")
    for (i = 1; i <= 3; i++) if (length(b[i]) == 1) b[i] = "0" b[i]
    if ((b[1] ":" b[2] ":" b[3]) in want) { ip = $2; gsub(/[()]/, "", ip); print ip }
  }' | sort -t. -k4 -n -u)
# a Pi slow to answer the 1 s sweep gets a second, longer chance before being
# taken for a stale entry
pis=""
for ip in $candidates; do
  if grep -q -x -F "$ip" <<<"$alive" || ping -c2 -t4 "$ip" >/dev/null 2>&1; then pis="$pis $ip"; fi
done
[[ -n "$pis" ]] || ko "no Raspberry Pi on the network: powered, and on the hotspot?"

fix_host_key() {
  local ip="$1" new known answer
  new=$(ssh-keyscan -t ed25519 "$ip" 2>/dev/null | ssh-keygen -lf - 2>/dev/null | awk '{print $2}')
  [[ -n "$new" ]] || { ko "$ip host key changed, and the new one cannot be read"; return 1; }
  known=$(ssh-keygen -lf ~/.ssh/known_hosts 2>/dev/null | awk -v fp="$new" -v ip="$ip" '$2 == fp && $3 != ip {print $3; exit}')
  if [[ -n "$known" ]]; then
    warn "$ip host key changed: the new key is the one known for $known (same Pi, new IP)"
  else
    warn "$ip host key changed to an unknown key $new (expected after a reflash, otherwise not your Pi)"
  fi
  read -rp "        ssh-keygen -R $ip ? [y/N] " answer
  [[ "$answer" == [yY] ]] || { ko "$ip skipped, host key not replaced"; return 1; }
  ssh-keygen -R "$ip" >/dev/null 2>&1
}

DEMO_IPS="" BACKUP_IP=""
for ip in $pis; do
  out=$("${SSH[@]}" "$PI_USER@$ip" hostname 2>&1)
  if [[ "$out" == *"HOST IDENTIFICATION HAS CHANGED"* ]]; then
    fix_host_key "$ip" || continue
    out=$("${SSH[@]}" "$PI_USER@$ip" hostname 2>&1)
  fi
  case "$out" in
    "$DEMO_HOSTNAME"*) DEMO_IPS="$DEMO_IPS $ip"; ok "$ip $out (demo)" ;;
    "$BACKUP_HOSTNAME") BACKUP_IP="$ip"; ok "$ip $out (backup)" ;;
    *reset*|*closed*|*refused*) warn "$ip SSH not ready (still booting?): run again in a minute" ;;
    *$'\n'*|*" "*) warn "$ip no SSH: $(tail -1 <<<"$out")" ;;
    *) warn "$ip is $out, neither $DEMO_HOSTNAME nor $BACKUP_HOSTNAME" ;;
  esac
done

pi_facts() {
  "${SSH[@]}" "$PI_USER@$1" bash -s -- "$HOTSPOT_SSID" <<'EOF'
echo "cloudinit=$(cloud-init status 2>/dev/null | awk '{print $2}')"
echo "boots=$(grep -c "running 'init-local'" /var/log/cloud-init.log 2>/dev/null)"
sudo -n true 2>/dev/null && echo "sudo=yes"
ssid=$(sudo -n iw dev wlan0 link 2>/dev/null | awk '/SSID:/{sub(/^[ \t]*SSID: /, ""); print}')
[ -n "$ssid" ] || ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | awk -F: '$1 == "yes" {print $2; exit}')
echo "ssid=$ssid"
{ nmcli -t -f NAME con show 2>/dev/null; sudo -n cat /etc/netplan/*.yaml 2>/dev/null; } | grep -q -- "$1" && echo "ssid_known=yes"
echo "memavail=$(awk '/MemAvailable/{print int($2 / 1024)}' /proc/meminfo)"
grep -q '^gpu_mem=16' /boot/firmware/config.txt && echo "tuned=yes"
echo "archives=$(ls /opt/kubesolo-demo/kubesolo-*-offline.tar.gz 2>/dev/null | wc -l)"
echo "images=$(ls /opt/kubesolo-demo/images/*.tar 2>/dev/null | wc -l)"
test -x /usr/sbin/iptables && echo "iptables=yes"
test -x /usr/local/bin/kubesolo && echo "kubesolo=yes"
echo "kubesolo_state=$(systemctl is-active kubesolo 2>/dev/null)"
cd ~/kubesolo-pizero 2>/dev/null && echo "scripts=$(find demo -maxdepth 1 -name '*.sh' | LC_ALL=C sort | xargs md5sum | awk '{print $1, $2}' | md5sum | cut -c1-32)"
EOF
}

fact() { sed -n "s/^$1=//p" <<<"$facts"; }

check_scripts() {
  if [[ "$(fact scripts)" == "$(scripts_hash_local)" ]]; then
    ok "Pi-side scripts (demo/*.sh) identical to the laptop"
  else
    fix "Pi-side scripts (demo/*.sh) missing or outdated" "ssh $PI_USER@$1 mkdir -p kubesolo-pizero && rsync -rlpt --delete $REPO_DIR/demo/ $PI_USER@$1:kubesolo-pizero/demo/"
  fi
}

check_wifi() {
  local ssid
  ssid=$(fact ssid)
  if [[ "$ssid" == "$HOTSPOT_SSID" ]]; then
    ok "wifi $ssid"
  elif [[ "$(fact ssid_known)" == yes ]]; then
    warn "wifi '${ssid:-?}', $HOTSPOT_SSID known: the Pi joins it when the current network is gone"
  else
    fix "wifi '${ssid:-?}' and $HOTSPOT_SSID unknown" "ssh -t $PI_USER@$1 'cd ~/kubesolo-pizero && sudo ./demo/10-os-tuning.sh wifi-add $HOTSPOT_SSID'"
  fi
}

for DEMO_IP in $DEMO_IPS; do
  title "Demo Pi $("${SSH[@]}" "$PI_USER@$DEMO_IP" hostname) ($DEMO_IP)"
  facts=$(pi_facts "$DEMO_IP")
  if [[ "$(fact cloudinit)" == done ]]; then ok "cloud-init done"; else warn "cloud-init '$(fact cloudinit)': first boot not finished?"; fi
  if [[ "$(fact tuned)" == yes ]]; then ko "OS tuning already applied: demos 01 to 06 show nothing, use a spare demo card"; else ok "stock OS, no tuning"; fi
  if [[ "$(fact kubesolo)" == yes ]]; then ko "KubeSolo already installed: demo 07 has nothing left to install, use a spare demo card"; else ok "KubeSolo not installed"; fi
  check_scripts "$DEMO_IP"
  if [[ "$(fact sudo)" == yes && "$(fact archives)" -ge 1 && "$(fact images)" -ge 2 && "$(fact iptables)" == yes ]]; then
    ok "prefetch done (KubeSolo archive, $(fact images) images, iptables, passwordless sudo)"
  else
    fix "prefetch missing" "ssh -t $PI_USER@$DEMO_IP 'cd ~/kubesolo-pizero && sudo ./demo/00-prefetch.sh'"
  fi
  check_wifi "$DEMO_IP"
  if [[ "$(fact boots)" -ge 2 ]]; then
    ok "rebooted since the first boot"
  else
    fix "still on the first boot, demo 06 would count cloud-init" "ssh -t $PI_USER@$DEMO_IP sudo systemctl reboot"
  fi
  ok "MemAvailable $(fact memavail) MiB"
  next
done

if [[ -n "$BACKUP_IP" ]]; then
  title "Backup Pi $BACKUP_HOSTNAME ($BACKUP_IP)"
  facts=$(pi_facts "$BACKUP_IP")
  check_scripts "$BACKUP_IP"
  check_wifi "$BACKUP_IP"
  ok "MemAvailable $(fact memavail) MiB"
  if [[ "$(fact kubesolo_state)" == active ]]; then ok "kubesolo active"; else ko "kubesolo $(fact kubesolo_state)"; fi
  if KUBECONFIG_OUT="$BACKUP_KUBECONFIG" "$REPO_DIR/demo/fetch-kubeconfig.sh" "$PI_USER@$BACKUP_IP" >/dev/null 2>&1; then
    # The Pi may have changed IP since the kubeconfig was written
    sed -i '' -E "s#(server: https://)[^:/]+#\1$BACKUP_IP#" "$BACKUP_KUBECONFIG"
    ok "kubeconfig in $BACKUP_KUBECONFIG"
    k=(kubectl --kubeconfig "$BACKUP_KUBECONFIG" --request-timeout=5s)
    if "${k[@]}" get --raw /readyz >/dev/null 2>&1; then
      ok "API ready"
      ready=$("${k[@]}" get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      if [[ "$ready" == True ]]; then ok "node Ready"; else ko "node not Ready"; fi
      if "${k[@]}" -n kube-system get pods -l k8s-app=coredns --no-headers 2>/dev/null | grep -q "1/1 *Running"; then
        ok "CoreDNS running"
      else
        warn "CoreDNS not ready yet (just booted?)"
      fi
    else
      ko "API unreachable on $BACKUP_IP:6443 (KubeSolo starting?)"
    fi
  else
    ko "cannot fetch the kubeconfig from $BACKUP_IP"
  fi
  next
fi

[[ -n "$DEMO_IPS" ]] || ko "demo Pi $DEMO_HOSTNAME* not found"
[[ -n "$BACKUP_IP" ]] || ko "backup Pi $BACKUP_HOSTNAME not found"

title "Menu"
env_prefix=""
[[ -n "${DEMO_ENV:-}" ]] && env_prefix="DEMO_ENV=$DEMO_ENV "
echo "  cd $REPO_DIR"
for DEMO_IP in $DEMO_IPS; do
  echo "  demo:   ${env_prefix}PI_HOST=$PI_USER@$DEMO_IP ./demo/talk/menu.sh"
done
[[ -n "$BACKUP_IP" ]] && echo "  backup: ${env_prefix}PI_HOST=$PI_USER@$BACKUP_IP PI_KUBECONFIG=$BACKUP_KUBECONFIG ./demo/talk/menu.sh"
echo
if (( FAILS == 0 )); then
  echo "${GREEN}Ready.${RESET}"
else
  echo "${RED}$FAILS problem(s).${RESET}"
fi
(( FAILS == 0 ))
