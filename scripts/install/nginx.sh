#!/usr/bin/env bash

ensure_nginx_installed() {
  if detect_nginx_installed; then
    log_info "Nginx already installed."
    return 0
  fi

  log_info "Nginx not detected; installing package."
  apt-get update
  apt-get install -y nginx
}

ensure_nginx_service_ready() {
  if ! service_enabled nginx; then
    log_info "Enabling nginx service."
    systemctl enable nginx
  else
    log_info "Nginx service already enabled."
  fi

  if ! service_active nginx; then
    log_info "Starting nginx service."
    systemctl start nginx
  else
    log_info "Nginx service already running."
  fi
}
