#!/usr/bin/env bash
# Demo 1 - the stock image: where did my 512 MB go?
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 01 "1 - Où sont passés mes 512 Mo ?" "$@"

pi "free -m"
pi "vcgencmd get_mem gpu"
pi "sudo ./demo/10-os-tuning.sh show"
