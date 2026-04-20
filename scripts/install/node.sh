#!/usr/bin/env bash

ensure_node_installed() {
  if command_exists node && command_exists npm; then
    log_info "Node.js and npm already installed."
    return 0
  fi

  log_info "Installing Node.js and npm from distribution packages."
  apt-get update
  apt-get install -y nodejs npm

  if command_exists node; then
    log_success "Node.js installed: $(node -v)"
  fi
}
