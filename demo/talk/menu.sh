#!/usr/bin/env bash
# Interactive demo launcher (fzf). Order follows the talk.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v fzf >/dev/null || { echo "fzf is missing: brew install fzf" >&2; exit 1; }

LABELS=(
  "00 Preflight        | Mac, IP et état des deux Pi"
  "01 Mémoire          | free, GPU, image d'origine"
  "02 Headless         | modules, timers, services"
  "03 Sessions         | systemd --user par connexion"
  "04 Mémoire          | min_free_kbytes, swappiness, zram, journal"
  "05 Cgroups + reboot | l'enquête du device tree, boot + network, reboot"
  "06 Bilan OS         | confirm, show, temps de boot"
  "07 KubeSolo         | install offline"
  "08 Cluster          | kubeconfig, nodes, pods"
  "09 nginx            | un vrai workload"
  "10 DOOM             | it runs DOOM"
  "11 Bonus            | une dernière chose..."
)

while true; do
  clear
  selection=$(printf '%s\n' "${LABELS[@]}" | fzf --prompt="Démo > " --header="KubeSolo sur Pi Zero 2 W" \
    --height=60% --border --reverse) || true
  [[ -z "$selection" ]] && exit 0

  script=$(ls "$SCRIPT_DIR/${selection:0:2}"-*.sh)
  echo ""
  echo "▶  $selection"
  echo "   Entrée pour démarrer..."
  read -rs _
  bash "$script" "$@" || true
  echo ""
  echo "Entrée pour revenir au menu..."
  read -rs _
done
