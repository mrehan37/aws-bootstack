#!/usr/bin/env bash

pm2_target_user() {
  resolve_node_target_user
}

run_as_pm2_user_with_nvm_script() {
  local script_path="$1"
  local target_user
  target_user="$(pm2_target_user)"

  su - "$target_user" -c "bash -lc 'set -e; export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; bash \"$script_path\"'"
}

run_as_pm2_user_with_nvm_cmd() {
  local command_text="$1"
  local cmd_script=""
  local rc=0

  cmd_script="$(mktemp /tmp/aws-bootstack-pm2-cmd.XXXXXX.sh)"
  printf '#!/usr/bin/env bash\nset -e\n%s\n' "$command_text" >"$cmd_script"
  chmod 700 "$cmd_script"

  if ! run_as_pm2_user_with_nvm_script "$cmd_script"; then
    rc=$?
  fi

  rm -f "$cmd_script"
  return "$rc"
}

pm2_available_for_user() {
  run_as_pm2_user_with_nvm_cmd "command -v pm2 >/dev/null 2>&1"
}

npm_available_for_user() {
  run_as_pm2_user_with_nvm_cmd "command -v npm >/dev/null 2>&1"
}

validate_pm2_app_name() {
  local app_name="$1"

  if ! [[ "$app_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    log_error "Invalid PM2 app name '$app_name'. Use only letters, numbers, dot, underscore, or hyphen."
    exit 1
  fi
}

ensure_pm2_installed() {
  local target_user
  target_user="$(pm2_target_user)"

  if pm2_available_for_user; then
    log_info "PM2 already installed for user '$target_user'."
    return 0
  fi

  if ! npm_available_for_user; then
    log_error "npm is required to install PM2 for '$target_user'. Install Node.js first."
    exit 1
  fi

  log_info "Installing PM2 for user '$target_user' (nvm context)."
  run_as_pm2_user_with_nvm_cmd "npm install -g pm2"
  log_success "PM2 installed successfully for user '$target_user'."
}

pm2_process_exists() {
  local app_name="$1"
  local quoted_name

  quoted_name="$(printf '%q' "$app_name")"
  run_as_pm2_user_with_nvm_cmd "pm2 describe ${quoted_name} >/dev/null 2>&1"
}

pm2_start_app() {
  local app_name="$1"
  local start_command="$2"
  local start_script=""
  local quoted_name=""
  local quoted_script=""

  start_script="$(mktemp /tmp/aws-bootstack-pm2-start.XXXXXX.sh)"
  trap 'rm -f "$start_script"' RETURN

  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$start_command" >"$start_script"
  chmod 700 "$start_script"

  quoted_name="$(printf '%q' "$app_name")"
  quoted_script="$(printf '%q' "$start_script")"

  run_as_pm2_user_with_nvm_cmd "pm2 start bash --name ${quoted_name} -- ${quoted_script}"
  run_as_pm2_user_with_nvm_cmd "pm2 save"
}

pm2_delete_app() {
  local app_name="$1"
  local quoted_name

  quoted_name="$(printf '%q' "$app_name")"
  run_as_pm2_user_with_nvm_cmd "pm2 delete ${quoted_name}"
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

  validate_pm2_app_name "$app_name"
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
