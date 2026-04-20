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

pm2_process_exists() {
  local app_name="$1"
  pm2 describe "$app_name" >/dev/null 2>&1
}

configure_pm2_app() {
  local app_name="$1"
  local start_command="$2"

  if [ -z "$app_name" ]; then
    log_error "PM2 app name is required."
    exit 1
  fi

  if [ -z "$start_command" ]; then
    log_error "PM2 start command is required."
    exit 1
  fi

  ensure_pm2_installed

  if pm2_process_exists "$app_name"; then
    if [ "${FORCE:-false}" = true ]; then
      log_warn "PM2 app '$app_name' already exists. Replacing due to --force."
      pm2 delete "$app_name"
    else
      log_warn "PM2 app '$app_name' already exists; skipping creation."
      return 0
    fi
  fi

  log_info "Starting PM2 app '$app_name' with provided command."
  pm2 start bash --name "$app_name" -- -lc "$start_command"
  pm2 save
  log_success "PM2 app '$app_name' started and saved."
}
