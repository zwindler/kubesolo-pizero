#!/usr/bin/env bash
# Demo 2 - a headless node does not need all that
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 02 "2 - Un node headless n'a pas besoin de..." "$@"

pi "lsmod | wc -l"
pi "lsmod | grep -E '^(bcm2835|snd|drm|vc4|videodev)' | cut -d' ' -f1"
pi "systemctl list-timers --no-pager --no-legend | awk '{print \$NF}'"
pi "sudo ./demo/10-os-tuning.sh services"
