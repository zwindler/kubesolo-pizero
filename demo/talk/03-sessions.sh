#!/usr/bin/env bash
# Demo 3 - one SSH login, one more systemd
. "$(dirname "${BASH_SOURCE[0]}")/demo-magic.sh"
demo_start 03 "3 - Une connexion SSH = un systemd de plus" "$@"

pi "ps -eo rss,user,args | grep -E '[s]ystemd --user|[s]d-pam|[s]ystemd-logind'"
pi "grep pam_systemd /etc/pam.d/common-session"
pi "sudo ./demo/10-os-tuning.sh sessions"
