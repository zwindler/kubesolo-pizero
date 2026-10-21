#!/usr/bin/env bash

###############################################################################
#
# demo-magic.sh
#
# Copyright (c) 2015-2022 Paxton Hare
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# This script lets you script demos in bash. It runs through your demo script
# when you press ENTER. It simulates typing and runs commands.
#
###############################################################################

# the speed to simulate typing the text
TYPE_SPEED=20

# no wait after "p" or "pe"
NO_WAIT=false
# display command without waiting
NO_WAIT_DISPLAY_CMD=false

# if > 0, will pause for this amount of seconds before automatically proceeding with any p or pe
PROMPT_TIMEOUT=0

# don't show command number unless user specifies it
SHOW_CMD_NUMS=false


# handy color vars for pretty prompts
BLACK="\033[0;30m"
BLUE="\033[0;34m"
GREEN="\033[0;32m"
GREY="\033[0;90m"
CYAN="\033[0;36m"
RED="\033[0;31m"
PURPLE="\033[0;35m"
BROWN="\033[0;33m"
WHITE="\033[0;37m"
BOLD="\033[1m"
COLOR_RESET="\033[0m"

C_NUM=0

# prompt and command color which can be overriden
DEMO_PROMPT="$ "
DEMO_CMD_COLOR=$BOLD
DEMO_COMMENT_COLOR=$GREY

##
# prints the script usage
##
function usage() {
  echo -e ""
  echo -e "Usage: $0 [options]"
  echo -e ""
  echo -e "  Where options is one or more of:"
  echo -e "  -h  Prints Help text"
  echo -e "  -d  Debug mode. Disables simulated typing"
  echo -e "  -n  No wait"
  echo -e "  -w  Waits max the given amount of seconds before "
  echo -e "      proceeding with demo (e.g. '-w5')"
  echo -e ""
}

##
# wait for user to press ENTER
# if $PROMPT_TIMEOUT > 0 this will be used as the max time for proceeding automatically
##
function wait() {
  if [[ "$PROMPT_TIMEOUT" == "0" ]]; then
    while true; do
      read -rsn1 key
      case "$key" in
        v|V)
          if [[ -n "${VIDEO_FALLBACK:-}" ]]; then
            play_video_fallback "$VIDEO_FALLBACK"
            exit 0
          fi
          ;;
        *) break ;;
      esac
    done
  else
    read -rst "$PROMPT_TIMEOUT"
  fi
}

##
# print command only. Useful for when you want to pretend to run a command
#
# takes 1 param - the string command to print
#
# usage: p "ls -l"
#
##
function p() {
  if [[ ${1:0:1} == "#" ]]; then
    cmd=$DEMO_COMMENT_COLOR$1$COLOR_RESET
  else
    cmd=$DEMO_CMD_COLOR$1$COLOR_RESET
  fi

  # render the prompt
  x=$(PS1="$DEMO_PROMPT" "$BASH" --norc -i </dev/null 2>&1 | sed -n '${s/^\(.*\)exit$/\1/p;}')

  # show command number is selected
  if $SHOW_CMD_NUMS; then
   printf "[$((++C_NUM))] $x"
  else
   printf "$x"
  fi

  # wait for the user to press a key before typing the command
  if [ "$NO_WAIT" = false ] && [ "$NO_WAIT_DISPLAY_CMD" = false ]; then
    wait
  fi

  if [[ -z $TYPE_SPEED ]]; then
    echo -en "$cmd"
  else
    echo -en "$cmd" | pv -qL $[$TYPE_SPEED+(-2 + RANDOM%5)];
  fi

  # wait for the user to press a key before moving on
  if [ $NO_WAIT = false ]; then
    wait
  fi
  echo ""
}

##
# Prints and executes a command
#
# takes 1 parameter - the string command to run
#
# usage: pe "ls -l"
#
##
function pe() {
  # print the command
  p "$@"
  run_cmd "$@"
}

##
# print and executes a command immediately
#
# takes 1 parameter - the string command to run
#
# usage: pei "ls -l"
#
##
function pei {
  NO_WAIT=true pe "$@"
}

##
# Enters script into interactive mode
#
# and allows newly typed commands to be executed within the script
#
# usage : cmd
#
##
function cmd() {
  # render the prompt
  x=$(PS1="$DEMO_PROMPT" "$BASH" --norc -i </dev/null 2>&1 | sed -n '${s/^\(.*\)exit$/\1/p;}')
  printf "$x\033[0m"
  read command
  run_cmd "${command}"
}

##
# Enters script into repl mode
#
# and allows newly typed commands to be executed within the script
#
# type exit to leave the repl
#
# usage : repl
#
##
function repl() {
  # render the prompt
  looping=true
  while $looping; do
    x=$(PS1="$DEMO_PROMPT" "$BASH" --norc -i </dev/null 2>&1 | sed -n '${s/^\(.*\)exit$/\1/p;}')
    printf "$x\033[0m"
    read command
    if [[ "$command" == "exit" ]]; then
      looping=false
    else
      run_cmd "$command"
    fi
  done
}

function run_cmd() {
  function handle_cancel() {
    printf ""
  }

  trap handle_cancel SIGINT
  stty -echoctl
  eval $@
  stty echoctl
  trap - SIGINT
}


function check_pv() {
  command -v pv >/dev/null 2>&1 || {

    echo ""
    echo -e "${RED}##############################################################"
    echo "# HOLD IT!! I require pv for simulated typing but it's " >&2
    echo "# not installed. Aborting." >&2;
    echo -e "${RED}##############################################################"
    echo ""
    echo -e "${COLOR_RESET}Disable simulated typing: "
    echo ""
    echo -e "   unset TYPE_SPEED"
    echo ""
    echo "Installing pv:"
    echo ""
    echo  "   Mac: $ brew install pv"
    echo ""
    echo  "   Other: https://www.ivarch.com/programs/pv.shtml"
    echo  ""
    exit 1;
  }
}

#
# handle some default params
# -h for help
# -d for disabling simulated typing
#
while getopts ":dhncw:" opt; do
  case $opt in
    h)
      usage
      exit 1
      ;;
    d)
      unset TYPE_SPEED
      ;;
    n)
      NO_WAIT=true
      ;;
    c)
      SHOW_CMD_NUMS=true
      ;;
    w)
      PROMPT_TIMEOUT=$OPTARG
      ;;
  esac
done

##
# Do not check for pv. This trusts the user to not set TYPE_SPEED later in the
# demo in which case an error will occur if pv is not installed.
##
if [[ -n "$TYPE_SPEED" ]]; then
  check_pv
fi

###############################################################################
#
# Extensions for the kubesolo-pizero talk. Everything runs on the laptop:
# pe runs a command locally, pi types it at a Pi prompt and runs it over SSH.
#
###############################################################################

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ -n "${DEMO_ENV:-}" && -f "$DEMO_ENV" ]]; then
  . "$DEMO_ENV"
fi
PI_HOST="${PI_HOST:?set PI_HOST (SSH host of the Pi), for example in the file pointed to by DEMO_ENV}"
PI_REPO="${PI_REPO:-kubesolo-pizero}"
PI_ADDR="${PI_ADDR:-$(ssh -G "$PI_HOST" | awk '/^hostname /{print $2}')}"
VNC_PASSWORD="${VNC_PASSWORD:-idbehold}"
VNCVIEWER="${VNCVIEWER:-/Applications/TigerVNC.app/Contents/MacOS/vncviewer}"
export KUBECONFIG="${PI_KUBECONFIG:-$REPO_DIR/kubeconfig-pizero}"

TYPE_SPEED=40
LAPTOP_PROMPT="${CYAN}laptop${COLOR_RESET} \$ "
DEMO_PROMPT="$LAPTOP_PROMPT"
PI_PROMPT="${GREEN}pi${COLOR_RESET}:${BLUE}~/${PI_REPO}${COLOR_RESET} \$ "

# One SSH connection for the whole demo: every pi command starts instantly.
# /tmp and not $TMPDIR: on macOS the latter makes the socket path too long.
SSH_OPTS=(-o ControlMaster=auto -o "ControlPath=/tmp/kubesolo-demo-%C" -o ControlPersist=15m
          -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=3
          -o LogLevel=ERROR)

function pi_ssh() {
  ssh "${SSH_OPTS[@]}" "$PI_HOST" "$@"
}

##
# pi "command" - types the command at the Pi prompt, runs it on the Pi from the
# copy of the repository
##
function pi() {
  DEMO_PROMPT="$PI_PROMPT"
  p "$1"
  DEMO_PROMPT="$LAPTOP_PROMPT"
  trap 'printf ""' SIGINT
  ssh "${SSH_OPTS[@]}" -t "$PI_HOST" "cd ~/${PI_REPO} 2>/dev/null; $1" || true
  trap - SIGINT
}

function section() {
  local title="$1"
  echo ""
  echo -e "${PURPLE}════════════════════════════════════════════════════════════${COLOR_RESET}"
  echo -e "${PURPLE}   $title${COLOR_RESET}"
  echo -e "${PURPLE}════════════════════════════════════════════════════════════${COLOR_RESET}"
  echo ""
}

function banner() {
  local text="$1"
  local color="${2:-$BROWN}"
  echo ""
  echo -e "${color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo -e "${color}  $text${COLOR_RESET}"
  echo -e "${color}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}"
  echo ""
}

function highlight_yaml() {
  local pattern="$1"
  local esc=$'\033'
  if [[ -n "${2:-}" ]]; then
    sed -E "s/($pattern)/${esc}[1;33m\1${esc}[0m/g" "$2"
  else
    sed -E "s/($pattern)/${esc}[1;33m\1${esc}[0m/g"
  fi
}

function play_video_fallback() {
  local video_path="$1"
  if [[ ! -f "$video_path" ]]; then
    echo -e "${RED}Fallback video not found: ${video_path}${COLOR_RESET}"
    return 1
  fi
  banner "Fallback video..." "$BROWN"
  open "$video_path"
}

##
# fallback_menu "message" - video, quit or continue anyway
##
function fallback_menu() {
  banner "$1" "$RED"
  echo -e "  ${BROWN}[v]${COLOR_RESET} fallback video"
  echo -e "  ${BROWN}[q]${COLOR_RESET} quit"
  echo -e "  ${BROWN}[c]${COLOR_RESET} continue anyway"
  while true; do
    read -rsn1 choice || exit 1
    case "$choice" in
      v|V) play_video_fallback "$VIDEO_FALLBACK"; exit 0 ;;
      q|Q) exit 1 ;;
      c|C) return 0 ;;
    esac
  done
}

function preflight_pi() {
  pi_ssh true 2>/dev/null || fallback_menu "No SSH to ${PI_HOST} (${PI_ADDR})"
}

function preflight_cluster() {
  kubectl get --raw /readyz >/dev/null 2>&1 || fallback_menu "Kubernetes API unreachable (KUBECONFIG=${KUBECONFIG})"
}

##
# wait_for_pi [seconds] - after a reboot, wait until SSH answers again
##
function wait_for_pi() {
  local timeout="${1:-60}" start=$SECONDS warned=false
  ssh "${SSH_OPTS[@]}" -O exit "$PI_HOST" >/dev/null 2>&1 || true
  echo -ne "${GREY}waiting for ${PI_HOST}${COLOR_RESET}"
  until pi_ssh true 2>/dev/null; do
    echo -n "."
    if ! $warned && (( SECONDS - start > timeout )); then
      warned=true
      banner "Nothing after ${timeout}s: unplug and plug the Pi back in" "$RED"
    fi
    sleep 2
  done
  echo -e " ${GREEN}up after $(( SECONDS - start ))s${COLOR_RESET}"
}

##
# demo_start <id> <title> "$@" - common start of every demo
##
function demo_start() {
  local id="$1" title="$2"
  shift 2
  VIDEO_FALLBACK="${VIDEO_DIR:+$VIDEO_DIR/$id.mp4}"
  if [[ "${1:-}" == "--video" ]]; then
    play_video_fallback "$VIDEO_FALLBACK"
    exit $?
  fi
  cd "$REPO_DIR"
  clear
  preflight_pi
  section "$title"
}

##
# vnc_password_file - TigerVNC password file (DES, fixed VNC key with bit-reversed bytes)
##
function vnc_password_file() {
  local f="${TMPDIR:-/tmp}/kubesolo-demo-vncpw" pw="${VNC_PASSWORD:0:8}"
  { printf '%s' "$pw"; (( ${#pw} < 8 )) && head -c $(( 8 - ${#pw} )) /dev/zero; } | /usr/bin/openssl enc -des-ecb -K e84ad660c4721ae0 -nopad -nosalt > "$f"
  echo "$f"
}

##
# wait_port <port> [seconds] - a new NodePort takes a few seconds to answer
##
function wait_port() {
  local port="$1" timeout="${2:-60}" start=$SECONDS
  until nc -z -G 1 "$PI_ADDR" "$port" 2>/dev/null; do
    (( SECONDS - start > timeout )) && return 1
    sleep 1
  done
}

##
# vnc_open <port> [geometry] - opens a TigerVNC window on the Pi, in the background
##
function vnc_open() {
  local port="$1" geometry="${2:-}"
  wait_port "$port" || echo -e "${RED}port ${port} still closed${COLOR_RESET}"
  "$VNCVIEWER" ${geometry:+-geometry "$geometry"} -PasswordFile "$(vnc_password_file)" -Shared "${PI_ADDR}::${port}" >/dev/null 2>&1 &
  echo $! >> "${TMPDIR:-/tmp}/kubesolo-demo-viewers"
}

function vnc_close_all() {
  local f="${TMPDIR:-/tmp}/kubesolo-demo-viewers"
  [[ -f "$f" ]] && xargs kill < "$f" 2>/dev/null
  rm -f "$f"
}
