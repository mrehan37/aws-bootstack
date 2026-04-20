#!/usr/bin/env bash

LAST_BACKUP=""

backup_file() {
  local target="$1"
  if [ ! -f "$target" ]; then
    log_warn "Backup skipped; file does not exist: $target"
    return 1
  fi

  LAST_BACKUP="$target.bak.$(date +%s)"
  cp "$target" "$LAST_BACKUP"
  log_info "Backup created: $LAST_BACKUP"
}

rollback_file() {
  local backup="$1"
  local target="$2"

  if [ -n "$backup" ] && [ -f "$backup" ]; then
    cp "$backup" "$target"
    log_warn "Rolled back $target from $backup"
  fi
}
