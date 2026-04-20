#!/usr/bin/env bash

request_domain_update_mode() {
  local domain="$1"
  local existing_config="$2"

  log_warn "Domain already configured: $domain"
  log_info "Existing config file: $existing_config" >&2
  log_info "Options:" >&2
  log_info "1) Skip" >&2
  log_info "2) Update config" >&2
  log_info "3) Overwrite completely" >&2

  choose_option "Choose [1-3] (default: 1): " "1"
}

configure_ssl_only() {
  local existing_config=""

  if ! detect_nginx_installed; then
    log_error "Nginx is not installed. Install nginx first, then re-run with --ssl-only."
    exit 1
  fi

  if ! existing_config="$(find_domain_config "$DOMAIN")"; then
    log_error "Domain '$DOMAIN' is not configured in nginx. Create domain config first, then run --ssl-only."
    exit 1
  fi

  if ! nginx -t >/dev/null 2>&1; then
    log_error "Current nginx configuration is invalid. Fix nginx config before running --ssl-only."
    exit 1
  fi

  log_info "Found existing domain config: $existing_config"
  ensure_ssl_certificate "$DOMAIN" "$existing_config"
  log_success "SSL-only flow completed for $DOMAIN"
}

configure_domain() {
  local existing_config=""
  local decision=""
  local config_path=""
  local final_ssl=false

  DOMAIN="$(sanitize_domain "$DOMAIN")"
  validate_domain "$DOMAIN"
  validate_port "$PORT"

  ensure_nginx_installed
  ensure_nginx_service_ready
  ensure_ufw_port_allowed 80
  ensure_ufw_port_allowed 443

  if existing_config="$(find_domain_config "$DOMAIN")"; then
    decision="$(request_domain_update_mode "$DOMAIN" "$existing_config")"
    case "$decision" in
      1)
        log_info "Skipping changes for existing domain $DOMAIN."
        return 0
        ;;
      2)
        config_path="$existing_config"
        ;;
      3)
        config_path="$(config_path_for_domain "$DOMAIN")"
        ;;
      *)
        log_error "Invalid selection: $decision"
        exit 1
        ;;
    esac
  else
    config_path="$(config_path_for_domain "$DOMAIN")"
    if [ -f "$config_path" ]; then
      log_warn "Config file exists at $config_path but domain match was not detected."
      decision="$(request_domain_update_mode "$DOMAIN" "$config_path")"
      case "$decision" in
        1)
          log_info "Skipping changes for existing config file $config_path."
          return 0
          ;;
        2)
          existing_config="$config_path"
          ;;
        3)
          ;;
        *)
          log_error "Invalid selection: $decision"
          exit 1
          ;;
      esac
    else
      log_info "Creating new Nginx config for $DOMAIN"
    fi
  fi

  if ssl_exists_for_domain "$DOMAIN"; then
    final_ssl=true
    log_info "Existing SSL detected for $DOMAIN."
  elif [ "${ENABLE_SSL:-false}" = true ]; then
    final_ssl=false
    log_info "SSL requested for $DOMAIN; HTTP config will be applied first."
  fi

  if [ -n "$existing_config" ] && [ "$decision" = "2" ]; then
    update_existing_domain_config "$existing_config" "$DOMAIN" "$PORT" "$PROXY_HOST"
  else
    write_domain_config "$DOMAIN" "$PORT" "$PROXY_HOST" "$final_ssl" "$config_path"
  fi

  if [ "${ENABLE_SSL:-false}" = true ] && ! ssl_exists_for_domain "$DOMAIN"; then
    ensure_ssl_certificate "$DOMAIN" "$config_path"
  fi

  log_success "Domain configuration complete for $DOMAIN"
}
