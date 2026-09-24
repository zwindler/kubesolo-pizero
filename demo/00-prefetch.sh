#!/usr/bin/env bash
# Run once before the talk, with network access. Downloads and verifies
# everything the live demo needs into /opt/kubesolo-demo.
set -euo pipefail

DIR=/opt/kubesolo-demo
KUBESOLO_VERSION=v1.2.0
KUBESOLO_ARCHIVE=kubesolo-${KUBESOLO_VERSION}-linux-arm64-offline.tar.gz
KUBESOLO_ARCHIVE_SHA256=9121d911c7d2c80a6224cf369e9594625e592e9a524789bae00f6fa9922a1069
KUBESOLO_INSTALLER_SHA256=49afcd5709f2146af052e2d32ca60b9ef65445e0dc42222282dee70f1f282083
DEBS=(iptables libip4tc2 libip6tc2 dropbear-bin libtomcrypt1 libtommath1)

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
mkdir -p "$DIR/debs"
cd "$DIR"

curl -fsSL -o install-kubesolo.sh "https://raw.githubusercontent.com/portainer/kubesolo/${KUBESOLO_VERSION}/install.sh"
echo "${KUBESOLO_INSTALLER_SHA256}  install-kubesolo.sh" | sha256sum -c -

if ! echo "${KUBESOLO_ARCHIVE_SHA256}  ${KUBESOLO_ARCHIVE}" | sha256sum -c - >/dev/null 2>&1; then
  curl -fL -o "$KUBESOLO_ARCHIVE" "https://github.com/portainer/kubesolo/releases/download/${KUBESOLO_VERSION}/${KUBESOLO_ARCHIVE}"
fi
echo "${KUBESOLO_ARCHIVE_SHA256}  ${KUBESOLO_ARCHIVE}" | sha256sum -c -

apt-get update -qq
cd debs && apt-get download "${DEBS[@]}" && cd ..

ls -la "$DIR" "$DIR/debs"
echo "prefetch OK"
