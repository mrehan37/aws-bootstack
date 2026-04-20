#!/usr/bin/env bash

COLOR_RESET='\033[0m'
COLOR_BOLD='\033[1m'
COLOR_DIM='\033[2m'
COLOR_RED='\033[31m'
COLOR_GREEN='\033[32m'
COLOR_YELLOW='\033[33m'
COLOR_BLUE='\033[34m'
COLOR_CYAN='\033[36m'

if [ ! -t 1 ] || [ "${NO_COLOR:-}" = "1" ] || [ "${TERM:-}" = "dumb" ]; then
  COLOR_RESET=''
  COLOR_BOLD=''
  COLOR_DIM=''
  COLOR_RED=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_CYAN=''
fi

log_info() {
  printf '%b[INFO]%b %s\n' "$COLOR_BLUE" "$COLOR_RESET" "$*"
}

log_warn() {
  printf '%b[WARN]%b %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$*" >&2
}

log_error() {
  printf '%b[ERROR]%b %s\n' "$COLOR_RED" "$COLOR_RESET" "$*" >&2
}

log_success() {
  printf '%b[SUCCESS]%b %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$*"
}

status_ok() {
  printf '%b%s%b' "$COLOR_GREEN" "$1" "$COLOR_RESET"
}

status_warn() {
  printf '%b%s%b' "$COLOR_YELLOW" "$1" "$COLOR_RESET"
}

status_bad() {
  printf '%b%s%b' "$COLOR_RED" "$1" "$COLOR_RESET"
}
