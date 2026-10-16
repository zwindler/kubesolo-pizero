#!/usr/bin/env bash
# Run once before the talk, with network access. Downloads and verifies
# everything the live demo needs into /opt/kubesolo-demo.
set -euo pipefail

DIR=/opt/kubesolo-demo
KUBESOLO_VERSION=v1.2.2
KUBESOLO_ARCHIVE=kubesolo-${KUBESOLO_VERSION}-linux-arm64-offline.tar.gz
KUBESOLO_ARCHIVE_SHA256=85ab7edb265b1f1559a1937b92eee8d6b0352c3c7fe78f4c641752b7cacc3a5c
KUBESOLO_INSTALLER_SHA256=185ec19b17b5884badc6e5a465e9ef87af454d631327da716d63e678e28f882d
DEBS=(iptables libip4tc2 libip6tc2)
# ctr must match the containerd embedded in KubeSolo (2.2.5 in v1.2.2).
CONTAINERD_VERSION=2.2.5
CONTAINERD_SHA256=ad3f7aec168ebbae8d24c412fdd2e8806d96599757f6032e38997d62a108158a
CRANE_VERSION=v0.22.1
CRANE_SHA256=898c0cff975f898a33e8c4580bdafb0e7c02c7faa33374e946762f97c4ab7110
IMAGES=(nginx:1.29-alpine-slim ghcr.io/zwindler/kubesolo-pizero/doom-vnc:latest)

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

# The talk scripts run sudo over SSH from the laptop, without a terminal to type
# a password in. Raspberry Pi Imager no longer sets this up.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  echo "$SUDO_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/010-kubesolo-demo
  chmod 440 /etc/sudoers.d/010-kubesolo-demo
  visudo -cqf /etc/sudoers.d/010-kubesolo-demo
  echo "passwordless sudo for $SUDO_USER"
fi

mkdir -p "$DIR/debs" "$DIR/bin" "$DIR/images"
cd "$DIR"

curl -fsSL -o install-kubesolo.sh "https://raw.githubusercontent.com/portainer/kubesolo/${KUBESOLO_VERSION}/install.sh"
echo "${KUBESOLO_INSTALLER_SHA256}  install-kubesolo.sh" | sha256sum -c -

if ! echo "${KUBESOLO_ARCHIVE_SHA256}  ${KUBESOLO_ARCHIVE}" | sha256sum -c - >/dev/null 2>&1; then
  curl -fL -o "$KUBESOLO_ARCHIVE" "https://github.com/portainer/kubesolo/releases/download/${KUBESOLO_VERSION}/${KUBESOLO_ARCHIVE}"
fi
echo "${KUBESOLO_ARCHIVE_SHA256}  ${KUBESOLO_ARCHIVE}" | sha256sum -c -
# The installer looks for it beside the archive.
curl -fsSL -o SHA256SUMS "https://github.com/portainer/kubesolo/releases/download/${KUBESOLO_VERSION}/SHA256SUMS"
grep "  ${KUBESOLO_ARCHIVE}$" SHA256SUMS | sha256sum -c -

apt-get update -qq
cd debs && apt-get -o APT::Sandbox::User=root download "${DEBS[@]}" && cd ..

if ! bin/ctr --version >/dev/null 2>&1; then
  curl -fsSL -o containerd.tar.gz "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-arm64.tar.gz"
  echo "${CONTAINERD_SHA256}  containerd.tar.gz" | sha256sum -c -
  tar -xzf containerd.tar.gz -C "$DIR" bin/ctr
  rm -f containerd.tar.gz
fi
if ! bin/crane version >/dev/null 2>&1; then
  curl -fsSL -o crane.tar.gz "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_arm64.tar.gz"
  echo "${CRANE_SHA256}  crane.tar.gz" | sha256sum -c -
  tar -xzf crane.tar.gz -C bin crane
  rm -f crane.tar.gz
fi
bin/ctr --version

# Fallback when the hotspot has no Internet: import them with import-images.sh.
for image in "${IMAGES[@]}"; do
  out="images/$(echo "${image##*/}" | tr ':' '_').tar"
  bin/crane pull --platform linux/arm64 "$image" "$out"
  echo "$image -> $out"
done

ls -la "$DIR" "$DIR/debs" "$DIR/images"
echo "prefetch OK"
