#!/usr/bin/env bash

ensure_ufw_port_allowed() {
  local port="$1"

  if ! detect_ufw_state; then
    log_warn "UFW not installed; skipping firewall configuration."
    return 0
  fi

  if ufw status | grep -Eq "(^|[[:space:]])${port}(/tcp)?[[:space:]]"; then
    log_info "UFW already allows port $port."
    return 0
  fi

  log_info "Allowing port $port through UFW."
  ufw allow "$port"/tcp
}
