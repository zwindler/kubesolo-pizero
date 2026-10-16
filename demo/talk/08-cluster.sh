#!/usr/bin/env bash
# Demo 8 - a Kubernetes node on a Pi Zero
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 08 "8 - Un node Kubernetes sur un Pi Zero" "$@"

p "./demo/fetch-kubeconfig.sh $PI_HOST"
KUBECONFIG_OUT="$KUBECONFIG" ./demo/fetch-kubeconfig.sh "$PI_HOST" >/dev/null
preflight_cluster
kubectl wait --for=condition=Ready node --all --timeout=300s >/dev/null 2>&1
until kubectl -n kube-system get pods -l k8s-app=coredns --no-headers 2>/dev/null | grep -q Running; do sleep 2; done
pe "kubectl get nodes -o wide"
pe "kubectl get pods -A"
pi "free -m"
