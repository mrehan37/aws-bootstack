# AWS Bootstack (Bash Server Bootstrap)

Production-style, idempotent server bootstrap for Ubuntu with safe nginx/domain/SSL handling.

`setup.sh` is the entrypoint and coordinator.  
All heavy logic lives in modular scripts under `scripts/`.

## What This Tool Does

- Detects system state before changing anything
- Configures nginx reverse proxy per domain
- Supports safe updates for existing domain configs
- Handles Let's Encrypt SSL with optional SSL-only flow
- Optionally installs Node.js and PM2
- Performs backup + validation (`nginx -t`) before reload
- Supports both interactive and CLI/non-interactive usage

## Project Structure

```text
setup.sh
scripts/
  core/
    logger.sh       # color logs + status rendering
    prompt.sh       # interactive prompts and confirmations
    validator.sh    # domain/port/root validation
    detector.sh     # system/domain/service/firewall detection + scan mode
  install/
    nginx.sh        # nginx install + service management
    node.sh         # node/npm install
    pm2.sh          # pm2 install
    ssl.sh          # certbot install + SSL issuance/reissue logic
    firewall.sh     # ufw detection + safe port allow
  config/
    nginx_config.sh # nginx server blocks, update/overwrite, nginx -t checks
    domain_manager.sh # domain decision flow + orchestration per domain
  utils/
    backup.sh       # timestamped backup + rollback helpers
    file_ops.sh     # safe file writes and symlink correctness
```

## Script One-Liners

- `setup.sh`: Entry-point coordinator that routes flags into modular workflows.
- `scripts/core/logger.sh`: Prints colored info/warn/error/success log lines.
- `scripts/core/prompt.sh`: Handles interactive input, choices, and confirmations.
- `scripts/core/validator.sh`: Validates root access plus domain/port correctness.
- `scripts/core/detector.sh`: Detects installed tools, services, domains, SSL, and firewall state.
- `scripts/install/nginx.sh`: Installs nginx and ensures service is enabled/running.
- `scripts/install/node.sh`: Installs Node.js and npm when missing.
- `scripts/install/pm2.sh`: Installs PM2 globally via npm.
- `scripts/install/ssl.sh`: Installs certbot and provisions/reissues certificates.
- `scripts/install/firewall.sh`: Applies idempotent UFW port rules.
- `scripts/config/nginx_config.sh`: Creates/updates nginx domain blocks with validation/rollback.
- `scripts/config/domain_manager.sh`: Orchestrates domain decisions (skip/update/overwrite/ssl-only).
- `scripts/utils/backup.sh`: Creates timestamped backups and restores from backup when needed.
- `scripts/utils/file_ops.sh`: Performs safe file writes and symlink corrections.

## Requirements

- Ubuntu/Debian server (uses `apt-get`)
- `systemd` available (`systemctl`)
- Root privileges (`sudo bash setup.sh ...`)
- DNS pointed to server before SSL issuance
- Ports `80` and `443` reachable for Let's Encrypt HTTP challenge

## Flags (One-Liners)

- `--scan`: Print detected nginx/domains/SSL/firewall/service state and exit.
- `--domain=DOMAIN`: Target domain to configure.
- `--port=PORT`: Upstream app port for proxying.
- `--proxy-host=HOST`: Upstream host for `proxy_pass` (default `127.0.0.1`).
- `--ssl`: Enable SSL issuance if cert is missing.
- `--ssl-only`: Configure/renew SSL for an existing domain only.
- `--with-node`: Ensure Node.js and npm are installed.
- `--node-version=VER`: Set Node.js channel (`lts`, `24`, `22`, `20`, `18`) for `--with-node` (installed via `nvm`).
- `--with-pm2`: Ensure PM2 is installed globally.
- `--pm2-name=NAME`: Set PM2 process name when creating a PM2 app.
- `--pm2-cmd=CMD`: Set PM2 startup command (supports env vars and chained commands).
- `--force`: Auto-accept safe defaults and skip interactive confirmations.
- `--non-interactive`: Fail instead of prompting when input/decision is needed.
- `--help`: Show usage.

## Working Cases

### 1) Inspect server state (read-only)

```bash
sudo bash setup.sh --scan
```

### 2) Interactive domain setup

```bash
sudo bash setup.sh
```

Flow:
- asks domain
- asks app port
- asks SSL yes/no
- asks if this is a Node.js project and desired Node.js version
- asks if PM2 should be configured (name + startup command)
- then applies safe domain configuration

### 3) New domain via CLI

```bash
sudo bash setup.sh --domain=example.com --port=3000
```

### 4) New domain with SSL

```bash
sudo bash setup.sh --domain=example.com --port=3000 --ssl
```

### 5) Existing domain: safe update vs overwrite

```bash
sudo bash setup.sh --domain=staging.example.com --port=4000
```

If domain/config exists, tool prompts:
- `1) Skip`
- `2) Update config` (safe path, targeted changes)
- `3) Overwrite completely`

### 6) SSL-only for existing domain

```bash
sudo bash setup.sh --domain=example.com --ssl-only
```

Behavior:
- requires existing nginx domain config
- validates `nginx -t` first
- handles cert issuance/reissue flow
- does not require or use app `--port`

### 7) Provision app runtime + domain in one run

```bash
sudo bash setup.sh --domain=api.example.com --port=5000 --with-node --with-pm2 --ssl
```

### 8) Runtime-only setup with explicit Node/PM2 config

```bash
sudo bash setup.sh --with-node --node-version=22 --with-pm2 --pm2-name=api --pm2-cmd="ENV_MODE=prod npm run prod"
```

## How It Works (Execution Flow)

## A) Entry Flow (`setup.sh`)

1. Loads all module scripts.
2. Parses flags.
3. If `--scan`, runs detection report and exits.
4. Requires root.
5. If `--ssl-only`, runs SSL-only pipeline and exits.
6. Optionally installs Node/PM2 if requested.
7. Runs interactive flow (no args) or CLI flow (with args).
8. Prints final server summary (nginx, domains, SSL count, Node.js, PM2 apps).

## B) Domain Setup Flow (`configure_domain`)

1. Validate/sanitize domain and validate port.
2. Ensure nginx is installed/running/enabled.
3. Ensure UFW rules for 80/443 (no duplicate rule insertions).
4. Detect existing domain config:
   - If found, ask `Skip / Update / Overwrite`.
   - If only config file exists (fallback), still ask decision.
5. Write/update config with backup safety.
6. Validate nginx config with `nginx -t`.
7. Reload nginx only if validation succeeds.
8. If SSL requested and not already present, issue certificate.
9. Print success line.

## C) SSL-Only Flow (`configure_ssl_only`)

1. Validate domain.
2. Ensure nginx is installed.
3. Ensure existing domain config exists.
4. Ensure current nginx config is valid.
5. Ensure certbot exists (or prompt/install based on mode).
6. Issue/reissue certificate using certbot nginx plugin.
7. Print success line.

## Safety and Idempotency Guarantees

- Detect-first approach for installs and services
- Domain existence checks before writes
- Timestamped backups before config modification
- Rollback path when nginx validation fails
- No full `nginx.conf` replacement
- Per-domain config file strategy in `sites-available` + symlink in `sites-enabled`
- Avoids duplicate UFW allow rules

## Validation Rules

- Domain must be FQDN-style (contains dot, valid labels)
- Port must be numeric and between `1` and `65535`
- Clear instructional errors are shown on invalid input

## SSL Renewal

Certbot renewal is handled by system timer/cron (standard apt install behavior).

Useful checks:

```bash
systemctl list-timers | grep certbot
sudo certbot renew --dry-run
```

## Notes

- For production parity tests, prefer a full Ubuntu VM over minimal Docker.
- Docker is fine for fast logic checks, but service behavior differs when `systemd` is absent.
