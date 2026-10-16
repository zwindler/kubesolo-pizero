#!/usr/bin/env bash
# Install KubeSolo from the files fetched by 00-prefetch.sh (no network needed).
set -euo pipefail

DIR=/opt/kubesolo-demo
KUBESOLO_VERSION=v1.2.2
KUBESOLO_ARCHIVE=kubesolo-${KUBESOLO_VERSION}-linux-arm64-offline.tar.gz
KUBESOLO_ARCHIVE_SHA256=85ab7edb265b1f1559a1937b92eee8d6b0352c3c7fe78f4c641752b7cacc3a5c
KUBECONFIG_PATH=/var/lib/kubesolo/pki/admin/admin.kubeconfig

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
start=$(date +%s)

if ! command -v iptables >/dev/null; then
  echo "==> iptables"
  dpkg -i "$DIR"/debs/libip4tc2_*.deb "$DIR"/debs/libip6tc2_*.deb "$DIR"/debs/iptables_*.deb >/dev/null
fi
iptables --version

echo "==> verifying ${KUBESOLO_ARCHIVE}"
echo "${KUBESOLO_ARCHIVE_SHA256}  ${DIR}/${KUBESOLO_ARCHIVE}" | sha256sum -c -

# Without NetworkManager there is no network-online target to wait for: KubeSolo
# would pick 127.0.0.1 as node IP if it starts before DHCP.
cat > /usr/local/sbin/wait-ipv4 <<'EOF'
#!/bin/sh
for _ in $(seq 1 60); do
  ip -4 -o addr show scope global | grep -q inet && exit 0
  sleep 1
done
exit 0
EOF
chmod 755 /usr/local/sbin/wait-ipv4

# Written before the installer so the very first start already runs with these
# settings. The installer writes /etc/kubesolo/config.yaml itself.
mkdir -p /etc/systemd/system/kubesolo.service.d
cat > /etc/systemd/system/kubesolo.service.d/10-pizero.conf <<'EOF'
[Service]
ExecStartPre=/usr/local/sbin/wait-ipv4
Environment=GOMEMLIMIT=220MiB
EOF

echo "==> installing KubeSolo ${KUBESOLO_VERSION} (offline build)"
sh "$DIR/install-kubesolo.sh" --offline-install="$DIR/$KUBESOLO_ARCHIVE" --local-storage=false | grep -E '✅|❌|⚠️' || true

echo "==> waiting for the admin kubeconfig"
until [ -f "$KUBECONFIG_PATH" ]; do
  systemctl is-active -q kubesolo || { echo "kubesolo is not running"; journalctl -u kubesolo -n 20 --no-pager; exit 1; }
  sleep 2
done

# The kubeconfig shows up before KubeSolo has imported its embedded images, the
# kubelet only starts afterwards.
echo "==> waiting for the kubelet"
until curl -sf -m 2 http://127.0.0.1:10248/healthz >/dev/null; do
  systemctl is-active -q kubesolo || { echo "kubesolo is not running"; journalctl -u kubesolo -n 20 --no-pager; exit 1; }
  sleep 2
done

echo "KubeSolo up in $(( $(date +%s) - start ))s, kubeconfig: $KUBECONFIG_PATH"
echo "from your laptop: ./demo/fetch-kubeconfig.sh <user>@<pi-address>"
