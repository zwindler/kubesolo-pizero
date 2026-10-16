#!/usr/bin/env bash
# Demo 11 - Kubernetes is made for scaling. So, can we scale DOOM?
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 11 "11 - Est-ce qu'on peut scaler DOOM ?" "$@"
preflight_cluster

REPLICAS=9
COLS=3

# One NodePort per pod (30911...) so that each window shows a different pod:
# the main Service would send every connection to a random one.
function open_doom_grid() {
  local i=0 pod
  for pod in $(kubectl -n doom get pods -l app=doom-grid -o go-template='{{range .items}}{{if and (eq .status.phase "Running") (not .metadata.deletionTimestamp)}}pod/{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | head -n "$REPLICAS"); do
    i=$((i + 1))
    kubectl -n doom label "$pod" --overwrite "doom-slot=$i" >/dev/null
    kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: doom-$i
  namespace: doom
  labels:
    demo: doom-grid
spec:
  type: NodePort
  selector:
    app: doom-grid
    doom-slot: "$i"
  ports:
    - port: 5900
      targetPort: vnc
      nodePort: $((30910 + i))
YAML
  done
  for i in $(seq 1 "$i"); do
    # x starts at 100: macOS pushes a window off a Dock on the left, which
    # would shift the first column only.
    vnc_open $((30910 + i)) "320x200+$(( 100 + ((i - 1) % COLS) * 360 ))+$(( 60 + ((i - 1) / COLS) * 270 ))"
  done
}

function close_doom_grid() {
  vnc_close_all
  kubectl -n doom delete svc -l demo=doom-grid --wait=false >/dev/null 2>&1
  kubectl delete -f demo/manifests/doom-grid.yaml --wait=false >/dev/null 2>&1
}

# A separate Deployment already at VNC_SCALE=1: scaling it creates pods
# without replacing any, a rollout on top of the scale-up is what pushed
# KubeSolo above GOMEMLIMIT during the tests.
vnc_close_all
p "# Kubernetes, c'est fait pour scaler..."
pe "kubectl apply -f demo/manifests/doom-grid.yaml"
pe "kubectl -n doom scale deploy/doom-grid --replicas=$REPLICAS"
kubectl -n doom rollout status deploy/doom-grid --timeout=180s >/dev/null 2>&1
pe "kubectl -n doom get pods -o wide"
open_doom_grid
pi "free -m"
pi "top -b -n 1 -o %CPU | head -20"

banner "Entrée pour tout ranger (fenêtres, Services, doom-grid)" "$BROWN"
wait
close_doom_grid
