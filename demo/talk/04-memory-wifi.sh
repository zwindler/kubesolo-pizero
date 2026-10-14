#!/usr/bin/env bash
# Demo 4 - sysctl, zram, journald, and the wifi that sleeps
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 04 "4 - MemAvailable et le wifi qui dort" "$@"

pe "ping -c 8 $PI_ADDR"
pi "sysctl vm.min_free_kbytes vm.swappiness vm.page-cluster"
pi "sudo ./demo/10-os-tuning.sh memory wifi"
pe "ping -c 8 $PI_ADDR"
