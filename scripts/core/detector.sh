#!/usr/bin/env bash

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
LETSENCRYPT_ROOT="/etc/letsencrypt/live"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_nginx_installed() {
  command_exists nginx
}

detect_certbot_installed() {
  command_exists certbot
}

detect_ufw_state() {
  command_exists ufw
}

service_active() {
  local service_name="$1"
  systemctl is-active --quiet "$service_name"
}

service_enabled() {
  local service_name="$1"
  systemctl is-enabled --quiet "$service_name"
}

config_path_for_domain() {
  local domain="$1"
  printf '%s/%s.conf' "$NGINX_SITES_AVAILABLE" "$domain"
}

enabled_path_for_domain() {
  local domain="$1"
  printf '%s/%s.conf' "$NGINX_SITES_ENABLED" "$domain"
}

ssl_exists_for_domain() {
  local domain="$1"
  [ -d "$LETSENCRYPT_ROOT/$domain" ]
}

extract_domain_from_server_name_line() {
  local line="$1"
  line="${line#*server_name}"
  line="${line%%;*}"
  awk '{print $1}' <<<"$line"
}

extract_proxy_pass_target() {
  local config_file="$1"
  local proxy_line=""
  proxy_line="$(grep -E '^[[:space:]]*proxy_pass[[:space:]]+http://' "$config_file" 2>/dev/null | head -n 1 || true)"
  proxy_line="${proxy_line#*http://}"
  proxy_line="${proxy_line%%;*}"
  printf '%s' "$proxy_line"
}

extract_port_from_proxy_target() {
  local proxy_target="$1"
  printf '%s' "${proxy_target##*:}"
}

find_domain_config() {
  local domain="$1"
  local found=""
  local escaped_domain=""
  local default_config_path=""

  if [ -d "$NGINX_SITES_AVAILABLE" ]; then
    escaped_domain="$(printf '%s' "$domain" | sed 's/[][(){}.+*?^$|\\/]/\\&/g')"
    found="$(grep -R -l -E "^[[:space:]]*server_name[[:space:]]+.*(^|[[:space:]])${escaped_domain}([[:space:];]|$)" "$NGINX_SITES_AVAILABLE" 2>/dev/null | head -n 1 || true)"
  fi

  if [ -n "$found" ]; then
    printf '%s' "$found"
    return 0
  fi

  # Fallback: if the conventional per-domain file exists, treat as existing config.
  default_config_path="$(config_path_for_domain "$domain")"
  if [ -f "$default_config_path" ]; then
    printf '%s' "$default_config_path"
    return 0
  fi

  return 1
}

detect_domains() {
  if [ ! -d "$NGINX_SITES_AVAILABLE" ]; then
    return 0
  fi

  local file
  local line
  local domain
  local proxy_target
  local port
  local ssl_label

  for file in "$NGINX_SITES_AVAILABLE"/*; do
    [ -f "$file" ] || continue
    line="$(grep -E '^[[:space:]]*server_name[[:space:]]+' "$file" | head -n 1 || true)"
    [ -n "$line" ] || continue
    domain="$(extract_domain_from_server_name_line "$line")"
    [ -n "$domain" ] || continue
    proxy_target="$(extract_proxy_pass_target "$file")"
    port="unknown"
    if [ -n "$proxy_target" ]; then
      port="$(extract_port_from_proxy_target "$proxy_target")"
    fi
    if ssl_exists_for_domain "$domain"; then
      ssl_label="enabled"
    else
      ssl_label="disabled"
    fi
    printf '%s|%s|%s|%s\n' "$domain" "$file" "$port" "$ssl_label"
  done
}

detect_pm2_apps() {
  if ! command_exists pm2; then
    return 0
  fi

  if ! command_exists node; then
    printf 'unknown|unknown|unknown\n'
    return 0
  fi

  pm2 jlist 2>/dev/null | node -e '
let input="";
process.stdin.on("data",c=>input+=c);
process.stdin.on("end",()=>{
  try {
    const apps = JSON.parse(input || "[]");
    if (!Array.isArray(apps) || apps.length === 0) return;
    for (const app of apps) {
      const name = app.name || "unknown";
      const status = (app.pm2_env && app.pm2_env.status) || "unknown";
      const mode = (app.pm2_env && app.pm2_env.exec_mode) || "unknown";
      process.stdout.write(`${name}|${status}|${mode}\n`);
    }
  } catch (_) {}
});
'
}

print_server_summary() {
  local domain=""
  local file=""
  local port=""
  local ssl_label=""
  local domain_entries=""
  local ssl_count=0
  local pm2_name=""
  local pm2_status=""
  local pm2_mode=""
  local pm2_entries=""
  local node_label=""
  local pm2_label=""

  while IFS='|' read -r domain file port ssl_label; do
    [ -n "$domain" ] || continue
    domain_entries="${domain_entries}  - ${domain} -> port ${port} (ssl: ${ssl_label})"$'\n'
    if [ "$ssl_label" = "enabled" ]; then
      ssl_count=$((ssl_count + 1))
    fi
  done < <(detect_domains)

  if command_exists node; then
    node_label="$(status_ok "$(node -v)")"
  else
    node_label="$(status_bad "Not installed")"
  fi

  if command_exists pm2; then
    pm2_label="$(status_ok "Installed")"
    while IFS='|' read -r pm2_name pm2_status pm2_mode; do
      [ -n "$pm2_name" ] || continue
      pm2_entries="${pm2_entries}  - ${pm2_name} (${pm2_status}, ${pm2_mode})"$'\n'
    done < <(detect_pm2_apps)
  else
    pm2_label="$(status_bad "Not installed")"
  fi

  printf '\n%sServer Summary%s\n' "$COLOR_BOLD" "$COLOR_RESET"
  printf -- '- Nginx: %s\n' "$(detect_nginx_installed && status_ok "Installed" || status_bad "Not installed")"
  printf -- '- Node.js: %s\n' "$node_label"
  printf -- '- PM2: %s\n' "$pm2_label"
  printf -- '- Domains:\n'
  if [ -n "$domain_entries" ]; then
    printf '%s' "$domain_entries"
  else
    printf '  - none\n'
  fi
  printf -- '- SSL-enabled domains: %s\n' "$ssl_count"
  if [ -n "$pm2_entries" ]; then
    printf -- '- PM2 apps:\n%s' "$pm2_entries"
  else
    printf -- '- PM2 apps:\n  - none\n'
  fi
}

scan_mode() {
  local nginx_label="Not installed"
  local firewall_label="Not installed"
  local active_ports="none"
  local domain_entries=""
  local ssl_count=0
  local domain=""
  local file=""
  local port=""
  local ssl_label=""

  if detect_nginx_installed; then
    nginx_label="$(status_ok "Installed")"
  else
    nginx_label="$(status_bad "Not installed")"
  fi

  if detect_ufw_state; then
    firewall_label="$(status_warn "Installed (inactive)")"
    if ufw status | grep -q "Status: active"; then
      firewall_label="$(status_ok "Active")"
      active_ports="$(ufw status | awk '/ALLOW/ {print $1}' | paste -sd ', ' -)"
      active_ports="${active_ports:-none}"
    fi
  else
    firewall_label="$(status_bad "Not installed")"
  fi

  while IFS='|' read -r domain file port ssl_label; do
    [ -n "$domain" ] || continue
    domain_entries="${domain_entries}  - ${domain} -> port ${port}"$'\n'
    if [ "$ssl_label" = "enabled" ]; then
      ssl_count=$((ssl_count + 1))
    fi
  done < <(detect_domains)

  printf 'Detected:\n'
  printf -- '- Nginx: %s\n' "$nginx_label"
  printf -- '- Domains:\n'
  if [ -n "$domain_entries" ]; then
    printf '%s' "$domain_entries"
  else
    printf '  - none\n'
  fi
  if [ "$ssl_count" -gt 0 ]; then
    printf -- '- SSL: Enabled for %b%s%b domain(s)\n' "$COLOR_GREEN" "$ssl_count" "$COLOR_RESET"
  else
    printf -- '- SSL: Enabled for %b%s%b domain(s)\n' "$COLOR_YELLOW" "$ssl_count" "$COLOR_RESET"
  fi
  printf -- '- Firewall: %s (ports %s)\n' "$firewall_label" "$active_ports"

  if detect_nginx_installed; then
    if service_active nginx; then
      printf -- '- Nginx service: %s' "$(status_ok "active")"
    else
      printf -- '- Nginx service: %s' "$(status_bad "inactive")"
    fi
    if service_enabled nginx; then
      printf ' / %s\n' "$(status_ok "enabled")"
    else
      printf ' / %s\n' "$(status_warn "disabled")"
    fi
  fi
}
