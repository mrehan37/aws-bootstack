#!/usr/bin/env bash

node_version_matches_request() {
  local requested_channel="$1"
  local installed_version=""
  local installed_major=""

  if ! command_exists node; then
    return 1
  fi

  installed_version="$(node -v 2>/dev/null || true)"
  installed_major="$(printf '%s' "$installed_version" | sed -E 's/^v([0-9]+).*/\1/')"

  case "$requested_channel" in
    lts)
      # LTS line changes over time; any installed node is acceptable unless forced.
      return 0
      ;;
    24|22|20|18)
      [ "$installed_major" = "$requested_channel" ]
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

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

install_nodejs_from_nodesource() {
  local requested_channel="$1"

  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings

  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  chmod a+r /etc/apt/keyrings/nodesource.gpg

  cat >/etc/apt/sources.list.d/nodesource.list <<EOF
deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${requested_channel}.x nodistro main
EOF

  apt-get update
  apt-get install -y nodejs
}

ensure_node_installed() {
  local requested_channel
  requested_channel="$(normalize_node_version_channel "${1:-lts}")"

  if command_exists node && command_exists npm; then
    if node_version_matches_request "$requested_channel"; then
      log_info "Node.js already installed: $(node -v)"
      return 0
    fi

    if [ "${FORCE:-false}" != true ]; then
      log_warn "Node.js $(node -v) already installed and requested channel is ${requested_channel}.x."
      log_warn "Skipping Node.js reinstall. Use --force to replace existing Node.js."
      return 0
    fi

    log_warn "Replacing existing Node.js due to --force."
  fi

  log_info "Installing Node.js ${requested_channel}.x from NodeSource."
  install_nodejs_from_nodesource "$requested_channel"

  if command_exists node; then
    log_success "Node.js installed: $(node -v)"
  fi

  if command_exists npm; then
    log_success "npm installed: $(npm -v)"
  else
    log_warn "npm binary not found after Node.js installation."
  fi
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
