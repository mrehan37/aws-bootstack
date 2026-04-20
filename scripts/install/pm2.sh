#!/usr/bin/env bash

ensure_pm2_installed() {
  if command_exists pm2; then
    log_info "PM2 already installed."
    return 0
  fi

  if ! command_exists npm; then
    log_error "npm is required to install PM2. Run with --with-node first."
    exit 1
  fi

  log_info "Installing PM2 globally."
  npm install -g pm2
  log_success "PM2 installed successfully."
}
