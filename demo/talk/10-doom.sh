#!/usr/bin/env bash
# Demo 10 - it runs DOOM
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 10 "10 - Does it run DOOM?" "$@"
preflight_cluster

pe "highlight_yaml 'image:|VNC_SCALE|resources:|memory:|cpu:|readOnlyRootFilesystem|nodePort:' demo/manifests/doom.yaml | sed -n '/^kind: Deployment/,\$p'"
pe "kubectl apply -f demo/manifests/doom.yaml"
kubectl -n doom rollout status deploy/doom --timeout=180s >/dev/null 2>&1
pe "kubectl -n doom get pods -o wide"
p "vncviewer $PI_ADDR:30900"
vnc_open 30900
