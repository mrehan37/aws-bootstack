#!/usr/bin/env bash

normalize_node_version_channel() {
  local raw="${1:-lts}"

  case "$raw" in
    lts|LTS|latest|latest-lts) printf 'lts' ;;
    24|24.x|v24) printf '24' ;;
    22|22.x|v22) printf '22' ;;
    20|20.x|v20) printf '20' ;;
    18|18.x|v18) printf '18' ;;
    *)
      log_error "Invalid node version '$raw'. Use one of: lts, 24, 22, 20, 18."
      exit 1
      ;;
  esac
}

node_selector_for_channel() {
  local channel="$1"

  case "$channel" in
    lts) printf '--lts' ;;
    24|22|20|18) printf "${channel}" ;;
    *)
      log_error "Unsupported node channel: $channel"
      exit 1
      ;;
  esac
}

resolve_node_target_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    printf '%s' "$SUDO_USER"
    return 0
  fi
  printf '%s' "${USER:-root}"
}

resolve_node_target_home() {
  local target_user="$1"
  local home_dir

  home_dir="$(getent passwd "$target_user" | cut -d: -f6 || true)"
  if [ -z "$home_dir" ]; then
    log_error "Unable to resolve home directory for user '$target_user'."
    exit 1
  fi
  printf '%s' "$home_dir"
}

ensure_nvm_installed_for_user() {
  local target_user="$1"
  local target_home="$2"
  local nvm_dir="${target_home}/.nvm"

  if [ -s "${nvm_dir}/nvm.sh" ]; then
    return 0
  fi

  log_info "Installing nvm for user '$target_user'."
  su - "$target_user" -c "bash -lc 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash'"
}

node_installed_for_user_channel() {
  local target_user="$1"
  local channel="$2"
  local selector
  selector="$(node_selector_for_channel "$channel")"

  su - "$target_user" -c "bash -lc 'export NVM_DIR=\"\$HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] || exit 1; . \"\$NVM_DIR/nvm.sh\"; nvm version ${selector} >/dev/null 2>&1'"
}

install_node_with_nvm() {
  local requested_channel="$1"
  local target_user="$2"
  local selector
  selector="$(node_selector_for_channel "$requested_channel")"

  if node_installed_for_user_channel "$target_user" "$requested_channel"; then
    log_info "Node.js channel '${requested_channel}' already installed via nvm for user '$target_user'."
  else
    log_info "Installing Node.js (${requested_channel}) via nvm for user '$target_user'."
    su - "$target_user" -c "bash -lc 'export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; nvm install ${selector}'"
  fi

  su - "$target_user" -c "bash -lc 'export NVM_DIR=\"\$HOME/.nvm\"; . \"\$NVM_DIR/nvm.sh\"; nvm alias default ${selector} >/dev/null; nvm use ${selector} >/dev/null; node -v; npm -v'" >/tmp/node_versions.$$ 2>/dev/null || true
  if [ -f /tmp/node_versions.$$ ]; then
    local node_ver
    local npm_ver
    node_ver="$(sed -n '1p' /tmp/node_versions.$$ || true)"
    npm_ver="$(sed -n '2p' /tmp/node_versions.$$ || true)"
    rm -f /tmp/node_versions.$$
    [ -n "$node_ver" ] && log_success "Node.js installed for '$target_user': $node_ver"
    [ -n "$npm_ver" ] && log_success "npm installed for '$target_user': $npm_ver"
  fi
}

ensure_node_installed() {
  local requested_channel
  local target_user
  local target_home

  requested_channel="$(normalize_node_version_channel "${1:-lts}")"

  target_user="$(resolve_node_target_user)"
  target_home="$(resolve_node_target_home "$target_user")"
  ensure_nvm_installed_for_user "$target_user" "$target_home"
  install_node_with_nvm "$requested_channel" "$target_user"
}

prompt_node_version_channel() {
  local choice=""

  log_info "Select Node.js version:" >&2
  log_info "1) latest LTS" >&2
  log_info "2) 24.x" >&2
  log_info "3) 22.x" >&2
  log_info "4) 20.x" >&2
  log_info "5) 18.x" >&2
  choice="$(choose_option "Choose [1-5] (default: 1): " "1")"

  case "$choice" in
    1) printf 'lts' ;;
    2) printf '24' ;;
    3) printf '22' ;;
    4) printf '20' ;;
    5) printf '18' ;;
    *)
      log_error "Invalid Node.js version choice: $choice"
      exit 1
      ;;
  esac
}
