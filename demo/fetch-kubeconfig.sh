#!/bin/sh
# Run on your laptop: copies the KubeSolo admin kubeconfig from the Pi.
set -eu
[ $# -eq 1 ] || { echo "usage: $0 <user>@<pi-address>"; exit 1; }
out=${KUBECONFIG_OUT:-./kubeconfig-pizero}
ssh "$1" sudo cat /var/lib/kubesolo/pki/admin/admin.kubeconfig > "$out"
chmod 600 "$out"
echo "export KUBECONFIG=$out"
