#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/scripts/core/logger.sh"
source "$SCRIPT_DIR/scripts/core/prompt.sh"
source "$SCRIPT_DIR/scripts/core/validator.sh"
source "$SCRIPT_DIR/scripts/core/detector.sh"
source "$SCRIPT_DIR/scripts/utils/backup.sh"
source "$SCRIPT_DIR/scripts/utils/file_ops.sh"
source "$SCRIPT_DIR/scripts/install/nginx.sh"
source "$SCRIPT_DIR/scripts/install/node.sh"
source "$SCRIPT_DIR/scripts/install/pm2.sh"
source "$SCRIPT_DIR/scripts/install/ssl.sh"
source "$SCRIPT_DIR/scripts/install/firewall.sh"
source "$SCRIPT_DIR/scripts/config/nginx_config.sh"
source "$SCRIPT_DIR/scripts/config/domain_manager.sh"

SCRIPT_NAME="$(basename "$0")"
FORCE=false
SCAN_MODE=false
ENABLE_SSL=false
SSL_ONLY=false
NON_INTERACTIVE=false
INSTALL_NODE=false
INSTALL_PM2=false
NODE_VERSION_CHANNEL=""
PM2_APP_NAME=""
PM2_START_COMMAND=""
DOMAIN=""
PORT=""
PROXY_HOST="127.0.0.1"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME [options]

Options:
  --scan                 Scan current system state and print a summary
  --domain=DOMAIN        Domain to configure
  --port=PORT            Upstream application port
  --proxy-host=HOST      Upstream host for proxy_pass (default: 127.0.0.1)
  --ssl                  Enable Let's Encrypt flow if certificate is missing
  --ssl-only             Configure/renew SSL for an existing domain only
  --with-node            Ensure Node.js is installed
  --node-version=VER     Node.js channel: lts|24|22|20|18 (used with --with-node)
  --with-pm2             Ensure PM2 is installed
  --pm2-name=NAME        PM2 process name (used with --with-pm2)
  --pm2-cmd=CMD          PM2 start command (used with --with-pm2)
  --force                Skip confirmations where safe
  --non-interactive      Fail instead of prompting when a decision is needed
  --help                 Show this help text

Examples:
  $SCRIPT_NAME --scan
  $SCRIPT_NAME --domain=example.com --port=3000 --ssl
  $SCRIPT_NAME --domain=example.com --ssl-only
  $SCRIPT_NAME --domain=api.example.com --port=5000 --with-node --with-pm2
  $SCRIPT_NAME --with-node --node-version=22 --with-pm2 --pm2-name=api --pm2-cmd="npm run start:prod"
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scan) SCAN_MODE=true ;;
      --domain=*) DOMAIN="${1#*=}" ;;
      --port=*) PORT="${1#*=}" ;;
      --proxy-host=*) PROXY_HOST="${1#*=}" ;;
      --ssl) ENABLE_SSL=true ;;
      --ssl-only) SSL_ONLY=true ;;
      --with-node) INSTALL_NODE=true ;;
      --node-version=*) NODE_VERSION_CHANNEL="${1#*=}" ;;
      --with-pm2) INSTALL_PM2=true ;;
      --pm2-name=*) PM2_APP_NAME="${1#*=}" ;;
      --pm2-cmd=*) PM2_START_COMMAND="${1#*=}" ;;
      --force) FORCE=true ;;
      --non-interactive) NON_INTERACTIVE=true ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

interactive_flow() {
  local node_project=false
  local pm2_project=false

  DOMAIN="$(ensure_value "domain" "Domain: " "$DOMAIN")"
  PORT="$(ensure_value "port" "App port: " "$PORT")"
  DOMAIN="$(sanitize_domain "$DOMAIN")"
  validate_domain "$DOMAIN"
  validate_port "$PORT"

  if [ "$ENABLE_SSL" = false ] && [ "$NON_INTERACTIVE" = false ]; then
    if confirm_yes_no "Enable SSL with Let's Encrypt?" "N"; then
      ENABLE_SSL=true
    fi
  fi

  if confirm_yes_no "Is this a Node.js project?" "N"; then
    node_project=true
    NODE_VERSION_CHANNEL="$(prompt_node_version_channel)"
    ensure_node_installed "$NODE_VERSION_CHANNEL"
  fi

  if confirm_yes_no "Do you want to configure PM2 for this app?" "N"; then
    pm2_project=true
    PM2_APP_NAME="$(ensure_value "pm2 app name" "PM2 app name: " "$PM2_APP_NAME")"
    PM2_START_COMMAND="$(ensure_value "pm2 start command" "PM2 start command: " "$PM2_START_COMMAND")"
    configure_pm2_app "$PM2_APP_NAME" "$PM2_START_COMMAND"
  fi

  configure_domain

  if [ "$node_project" = true ] || [ "$pm2_project" = true ]; then
    log_success "Application runtime setup completed."
  fi
}

main() {
  parse_args "$@"

  if [ "$SCAN_MODE" = true ]; then
    scan_mode
    exit 0
  fi

  require_root

  if [ "$SSL_ONLY" = true ]; then
    ENABLE_SSL=true
    if [ -n "$PORT" ]; then
      log_warn "--ssl-only ignores --port."
    fi
    DOMAIN="$(ensure_value "domain" "Domain: " "$DOMAIN")"
    DOMAIN="$(sanitize_domain "$DOMAIN")"
    validate_domain "$DOMAIN"
    configure_ssl_only
    print_server_summary
    exit 0
  fi

  if [ "$INSTALL_NODE" = true ]; then
    ensure_node_installed "${NODE_VERSION_CHANNEL:-lts}"
  fi

  if [ "$INSTALL_PM2" = true ]; then
    if [ -n "$PM2_APP_NAME" ] || [ -n "$PM2_START_COMMAND" ]; then
      PM2_APP_NAME="$(ensure_value "pm2 app name" "" "$PM2_APP_NAME")"
      PM2_START_COMMAND="$(ensure_value "pm2 start command" "" "$PM2_START_COMMAND")"
      configure_pm2_app "$PM2_APP_NAME" "$PM2_START_COMMAND"
    else
      ensure_pm2_installed
    fi
  fi

  if { [ "$INSTALL_NODE" = true ] || [ "$INSTALL_PM2" = true ]; } && [ -z "$DOMAIN" ] && [ -z "$PORT" ]; then
    log_info "Runtime setup completed without domain configuration."
    print_server_summary
    exit 0
  fi

  if [ -n "$DOMAIN" ] || [ -n "$PORT" ] || [ "$NON_INTERACTIVE" = true ]; then
    DOMAIN="$(ensure_value "domain" "" "$DOMAIN")"
    PORT="$(ensure_value "port" "" "$PORT")"
    configure_domain
    print_server_summary
    exit 0
  fi

  interactive_flow
  print_server_summary
}

main "$@"
