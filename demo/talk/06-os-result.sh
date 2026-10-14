#!/usr/bin/env bash
# Demo 6 - after the reboot: confirm the network change, OS result
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
VIDEO_FALLBACK="${VIDEO_DIR:+$VIDEO_DIR/06.mp4}"
cd "$REPO_DIR"
clear
section "6 - Bilan OS"
wait_for_pi 60

pi "sudo ./demo/10-os-tuning.sh confirm show"
pi "cat /sys/fs/cgroup/cgroup.subtree_control"
pi "systemd-analyze"
