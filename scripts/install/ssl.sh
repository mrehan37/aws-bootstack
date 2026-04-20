#!/usr/bin/env bash

ensure_certbot_installed() {
  if detect_certbot_installed; then
    log_info "Certbot already installed."
    return 0
  fi

  log_info "Certbot not detected; installing package."
  apt-get update
  apt-get install -y certbot python3-certbot-nginx
}

ensure_ssl_certificate() {
  local domain="$1"
  local config_path="$2"

  if ssl_exists_for_domain "$domain"; then
    log_warn "SSL certificate already exists for $domain"
    if [ "${FORCE:-false}" != true ] && ! confirm_yes_no "Reissue certificate for $domain?" "N"; then
      log_info "Keeping existing certificate for $domain."
      return 0
    fi
  fi

  if ! detect_certbot_installed; then
    if [ "${SSL_ONLY:-false}" = true ]; then
      if [ "${NON_INTERACTIVE:-false}" = true ]; then
        log_error "Certbot is required for --ssl-only but is not installed. Install certbot, then re-run."
        exit 1
      fi

      if confirm_yes_no "Certbot is not installed. Install certbot now?" "N"; then
        ensure_certbot_installed
      else
        log_error "Cannot continue SSL setup without certbot."
        exit 1
      fi
    else
      ensure_certbot_installed
    fi
  fi

  log_info "Requesting Let's Encrypt certificate for $domain"
  certbot --nginx -d "$domain" --non-interactive --agree-tos --register-unsafely-without-email --redirect

  if [ ! -f "$config_path" ]; then
    log_warn "Certbot completed, but expected config file missing: $config_path"
  fi
}
