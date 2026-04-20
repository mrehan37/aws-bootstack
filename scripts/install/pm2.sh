#!/usr/bin/env bash

pm2_target_user() {
  resolve_node_target_user
}

run_as_pm2_user_with_nvm() {
  local cmd="$1"
  local target_user
  target_user="$(pm2_target_user)"
  su - "$target_user" -c "bash -lc 'export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; ${cmd}'"
}

ensure_pm2_installed() {
  if command_exists pm2; then
    log_info "PM2 already installed."
    return 0
  fi

  if command_exists npm; then
    log_info "Installing PM2 globally (system npm)."
    npm install -g pm2
    log_success "PM2 installed successfully."
    return 0
  fi

  local target_user
  target_user="$(pm2_target_user)"

  if ! run_as_pm2_user_with_nvm "command -v npm >/dev/null 2>&1"; then
    log_error "npm is required to install PM2. Install Node.js first."
    exit 1
  fi

  log_info "Installing PM2 for user '$target_user' via npm (nvm environment)."
  run_as_pm2_user_with_nvm "npm install -g pm2"
  log_success "PM2 installed successfully for user '$target_user'."
}

pm2_process_exists() {
  local app_name="$1"

  if command_exists pm2; then
    pm2 describe "$app_name" >/dev/null 2>&1
    return $?
  fi

  run_as_pm2_user_with_nvm "pm2 describe \"$app_name\" >/dev/null 2>&1"
}

pm2_start_app() {
  local app_name="$1"
  local start_command="$2"

  if command_exists pm2; then
    pm2 start bash --name "$app_name" -- -lc "$start_command"
    pm2 save
    return 0
  fi

  run_as_pm2_user_with_nvm "pm2 start bash --name \"$app_name\" -- -lc \"$start_command\""
  run_as_pm2_user_with_nvm "pm2 save"
}

pm2_delete_app() {
  local app_name="$1"

  if command_exists pm2; then
    pm2 delete "$app_name"
    return 0
  fi

  run_as_pm2_user_with_nvm "pm2 delete \"$app_name\""
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
      pm2_delete_app "$app_name"
    else
      log_warn "PM2 app '$app_name' already exists; skipping creation."
      return 0
    fi
  fi

  log_info "Starting PM2 app '$app_name' with provided command."
  pm2_start_app "$app_name" "$start_command"
  log_success "PM2 app '$app_name' started and saved."
}
