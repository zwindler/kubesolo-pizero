#!/usr/bin/env bash
# Demo 7 - KubeSolo offline install
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 07 "7 - KubeSolo, en offline" "$@"

pi "ls -lh /opt/kubesolo-demo"
pi "sudo ./demo/20-kubesolo.sh"
