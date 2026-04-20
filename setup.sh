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
  --with-pm2             Ensure PM2 is installed
  --force                Skip confirmations where safe
  --non-interactive      Fail instead of prompting when a decision is needed
  --help                 Show this help text

Examples:
  $SCRIPT_NAME --scan
  $SCRIPT_NAME --domain=example.com --port=3000 --ssl
  $SCRIPT_NAME --domain=example.com --ssl-only
  $SCRIPT_NAME --domain=api.example.com --port=5000 --with-node --with-pm2
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
      --with-pm2) INSTALL_PM2=true ;;
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

  configure_domain
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
    exit 0
  fi

  if [ "$INSTALL_NODE" = true ]; then
    ensure_node_installed
  fi

  if [ "$INSTALL_PM2" = true ]; then
    ensure_pm2_installed
  fi

  if [ -n "$DOMAIN" ] || [ -n "$PORT" ] || [ "$NON_INTERACTIVE" = true ]; then
    DOMAIN="$(ensure_value "domain" "" "$DOMAIN")"
    PORT="$(ensure_value "port" "" "$PORT")"
    configure_domain
    exit 0
  fi

  interactive_flow
}

main "$@"
