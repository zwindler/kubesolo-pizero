#!/usr/bin/env bash
# Demo 4 - min_free_kbytes, zram, journald
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 04 "4 - MemAvailable et zram" "$@"

pi "sudo sysctl vm.min_free_kbytes vm.swappiness vm.page-cluster"
pi "sudo ./demo/10-os-tuning.sh memory"
