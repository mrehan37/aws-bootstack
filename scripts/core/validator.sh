#!/usr/bin/env bash

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    log_error "This script must be run as root."
    exit 1
  fi
}

sanitize_domain() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_domain() {
  local domain="$1"
  # Enforce FQDN-style domains for predictable nginx/certbot behavior.
  # Examples accepted: example.com, api.example.com
  # Examples rejected: localhost, sad, .example.com, example..com
  if [[ "$domain" != *.* ]]; then
    log_error "Invalid domain '$domain': must contain at least one dot (e.g. example.com)."
    exit 1
  fi

  if [[ "$domain" =~ \.\. ]]; then
    log_error "Invalid domain '$domain': consecutive dots are not allowed."
    exit 1
  fi

  if ! [[ "$domain" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; then
    log_error "Invalid domain '$domain': use a valid FQDN like example.com or api.example.com."
    exit 1
  fi
}

validate_port() {
  local port="$1"
  if ! [[ "$port" =~ ^[0-9]+$ ]]; then
    log_error "Invalid port '$port': port must be a number (e.g. 3000)."
    exit 1
  fi

  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    log_error "Invalid port '$port': port must be between 1 and 65535."
    exit 1
  fi
}
