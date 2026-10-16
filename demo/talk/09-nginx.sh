#!/usr/bin/env bash
# Demo 9 - a real workload
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 09 "9 - nginx" "$@"
preflight_cluster

pe "highlight_yaml 'image:|resources:|memory:|cpu:|nodePort:|worker_processes' demo/manifests/nginx.yaml | sed -n '/^kind: Deployment/,\$p'"
pe "kubectl apply -f demo/manifests/nginx.yaml"
kubectl -n nginx rollout status deploy/nginx --timeout=180s >/dev/null 2>&1
pe "kubectl -n nginx get pods -o wide"
pe "curl -s http://$PI_ADDR:30080"
