#!/usr/bin/env bash

generate_http_server_block() {
  local domain="$1"
  local port="$2"
  local host="$3"

  cat <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://$host:$port;
    }
}
EOF
}

generate_https_server_block() {
  local domain="$1"
  local port="$2"
  local host="$3"

  cat <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;

    ssl_certificate /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://$host:$port;
    }
}
EOF
}

replace_or_append_proxy_pass() {
  local config_path="$1"
  local host="$2"
  local port="$3"

  if grep -Eq '^[[:space:]]*proxy_pass[[:space:]]+http://' "$config_path"; then
    sed -i -E "s|^[[:space:]]*proxy_pass[[:space:]]+http://[^;]+;|        proxy_pass http://${host}:${port};|g" "$config_path"
  else
    log_warn "No proxy_pass line found in $config_path; appending a managed location block."
    cat >>"$config_path" <<EOF

location / {
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_pass http://$host:$port;
}
EOF
  fi
}

update_existing_domain_config() {
  local config_path="$1"
  local domain="$2"
  local port="$3"
  local host="$4"

  backup_file "$config_path"
  replace_or_append_proxy_pass "$config_path" "$host" "$port"

  if grep -Eq '^[[:space:]]*server_name[[:space:]]+' "$config_path"; then
    sed -i -E "0,/^[[:space:]]*server_name[[:space:]]+.*/s//    server_name ${domain};/" "$config_path"
  else
    log_warn "No server_name directive found in $config_path; prepending one."
    local tmp_file
    tmp_file="$(mktemp)"
    {
      printf 'server_name %s;\n' "$domain"
      cat "$config_path"
    } >"$tmp_file"
    cp "$tmp_file" "$config_path"
    rm -f "$tmp_file"
  fi

  if nginx -t; then
    systemctl reload nginx
    log_success "Nginx reloaded successfully."
  else
    log_error "Nginx config validation failed after update."
    rollback_file "$LAST_BACKUP" "$config_path"
    nginx -t || true
    exit 1
  fi
}

write_domain_config() {
  local domain="$1"
  local port="$2"
  local host="$3"
  local ssl_enabled="$4"
  local config_path="${5:-}"
  local enabled_path
  local tmp_file

  if [ -z "$config_path" ]; then
    config_path="$(config_path_for_domain "$domain")"
  fi

  enabled_path="$(enabled_path_for_domain "$domain")"
  tmp_file="$(mktemp)"

  if [ "$ssl_enabled" = true ]; then
    generate_https_server_block "$domain" "$port" "$host" >"$tmp_file"
  else
    generate_http_server_block "$domain" "$port" "$host" >"$tmp_file"
  fi

  safe_write_file "$config_path" "$tmp_file"
  rm -f "$tmp_file"

  ensure_symlink_points_to "$enabled_path" "$config_path"

  if nginx -t; then
    systemctl reload nginx
    log_success "Nginx reloaded successfully."
  else
    log_error "Nginx config validation failed."
    if [ -n "$LAST_BACKUP" ]; then
      rollback_file "$LAST_BACKUP" "$config_path"
    else
      rm -f "$config_path"
      rm -f "$enabled_path"
      log_warn "Removed new config for $domain after failed validation."
    fi
    nginx -t || true
    exit 1
  fi
}
