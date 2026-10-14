#!/usr/bin/env bash
# Imports the image archives fetched by 00-prefetch.sh, for a hotspot without
# Internet access. Since KubeSolo v1.2.1 imported images survive restarts.
set -euo pipefail

DIR=/opt/kubesolo-demo
SOCK=/var/lib/kubesolo/containerd/containerd.sock
CTR=("$DIR/bin/ctr" -a "$SOCK" -n k8s.io)

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

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
