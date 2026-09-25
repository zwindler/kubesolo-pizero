#!/usr/bin/env bash
# KubeSolo v1.2.0 wipes its containerd content store at every start (upstream #197):
# re-import the image archives fetched by 00-prefetch.sh.
#   import-images.sh            import now (waits for KubeSolo's containerd)
#   import-images.sh --install  do it automatically at every KubeSolo start
set -euo pipefail

DIR=/opt/kubesolo-demo
SOCK=/var/lib/kubesolo/containerd/containerd.sock
CTR=("$DIR/bin/ctr" -a "$SOCK" -n k8s.io)

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

if [ "${1:-}" = "--install" ]; then
  install -m 755 "$0" "$DIR/import-images.sh"
  cat > /etc/systemd/system/kubesolo-import-images.service <<UNIT
[Unit]
Description=Re-import local images after each KubeSolo start
After=kubesolo.service
PartOf=kubesolo.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$DIR/import-images.sh
TimeoutStartSec=600

[Install]
WantedBy=kubesolo.service
UNIT
  systemctl daemon-reload
  systemctl enable kubesolo-import-images.service
  echo "installed: images re-imported at every KubeSolo start"
  exit 0
fi

# KubeSolo imports its own embedded images at startup under a deadline and exits
# if that import is slowed down. The kubelet only starts once it is done.
for _ in $(seq 1 600); do
  curl -sf -m 2 http://127.0.0.1:10248/healthz >/dev/null && break
  sleep 1
done
"${CTR[@]}" version >/dev/null

for archive in "$DIR"/images/*.tar; do
  [ -e "$archive" ] || continue
  "${CTR[@]}" images import --local --platform linux/arm64 "$archive" | sed "s|^|$(basename "$archive"): |"
done
"${CTR[@]}" images ls -q | grep -v '^sha256:'
