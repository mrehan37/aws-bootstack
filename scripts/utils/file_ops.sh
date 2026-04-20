#!/usr/bin/env bash

ensure_symlink_points_to() {
  local symlink_path="$1"
  local target_path="$2"

  if [ -e "$symlink_path" ] && [ ! -L "$symlink_path" ]; then
    backup_file "$symlink_path" || true
    rm -f "$symlink_path"
  fi

  if [ -L "$symlink_path" ] && [ "$(readlink "$symlink_path")" != "$target_path" ]; then
    rm -f "$symlink_path"
  fi

  if [ ! -L "$symlink_path" ]; then
    ln -s "$target_path" "$symlink_path"
  fi
}

safe_write_file() {
  local target="$1"
  local source_tmp="$2"

  if [ -f "$target" ]; then
    backup_file "$target" || true
  else
    LAST_BACKUP=""
  fi

  cp "$source_tmp" "$target"
}
