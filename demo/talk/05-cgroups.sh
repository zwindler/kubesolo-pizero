#!/usr/bin/env bash
# Demo 5 - the device tree that disables the memory cgroup, then boot + network and reboot
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 05 "5 - Le device tree qui désactive les cgroups" "$@"

pi "cat /sys/fs/cgroup/cgroup.subtree_control"
pi "cat /proc/cmdline"
pi "cat /boot/firmware/cmdline.txt"
pi "grep -l -a cgroup_disable=memory /boot/firmware/*.dtb"
pi "sudo ./demo/10-os-tuning.sh boot network"
pi "sudo ./demo/10-os-tuning.sh reboot"
ssh "${SSH_OPTS[@]}" -O exit "$PI_HOST" >/dev/null 2>&1 || true
banner "Reboot en cours : retour aux slides (~15 s)" "$BROWN"
