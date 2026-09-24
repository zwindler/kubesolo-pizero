#!/usr/bin/env bash
# Install KubeSolo from the files fetched by 00-prefetch.sh (no network needed).
set -euo pipefail

DIR=/opt/kubesolo-demo
KUBESOLO_VERSION=v1.2.0
KUBESOLO_ARCHIVE=kubesolo-${KUBESOLO_VERSION}-linux-arm64-offline.tar.gz
KUBESOLO_ARCHIVE_SHA256=9121d911c7d2c80a6224cf369e9594625e592e9a524789bae00f6fa9922a1069
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

# Written before the installer so the very first start already runs with these
# settings. ExecStart is overridden because the v1.2.0 installer renders boolean
# options as --flag=false, which the v1.2.0 binary rejects.
mkdir -p /etc/systemd/system/kubesolo.service.d
cat > /etc/systemd/system/kubesolo.service.d/10-pizero.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/local/bin/kubesolo --path=/var/lib/kubesolo --no-local-storage
Environment=GOMEMLIMIT=180MiB
TimeoutStopSec=30
ExecStopPost=/bin/systemctl --no-block stop kubepods.slice
EOF

echo "==> installing KubeSolo ${KUBESOLO_VERSION} (offline build)"
sh "$DIR/install-kubesolo.sh" --offline-install="$DIR/$KUBESOLO_ARCHIVE" | grep -E '✅|❌|⚠️' || true

echo "==> waiting for the admin kubeconfig"
until [ -f "$KUBECONFIG_PATH" ]; do
  systemctl is-active -q kubesolo || { echo "kubesolo is not running"; journalctl -u kubesolo -n 20 --no-pager; exit 1; }
  sleep 2
done

echo "KubeSolo up in $(( $(date +%s) - start ))s, kubeconfig: $KUBECONFIG_PATH"
echo "from your laptop: ./demo/fetch-kubeconfig.sh <user>@<pi-address>"
