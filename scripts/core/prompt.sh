#!/usr/bin/env bash

ensure_value() {
  local variable_name="$1"
  local prompt_text="$2"
  local current_value="$3"
  local input=""

  if [ -n "$current_value" ]; then
    printf '%s' "$current_value"
    return 0
  fi

  if [ "${NON_INTERACTIVE:-false}" = true ]; then
    log_error "Missing required value for $variable_name in non-interactive mode."
    exit 1
  fi

  read -r -p "$prompt_text" input
  if [ -z "$input" ]; then
    log_error "$variable_name cannot be empty."
    exit 1
  fi

  printf '%s' "$input"
}

choose_option() {
  local prompt="$1"
  local default_choice="$2"
  local choice=""

  if [ "${FORCE:-false}" = true ]; then
    printf '%s' "$default_choice"
    return 0
  fi

  if [ "${NON_INTERACTIVE:-false}" = true ]; then
    log_error "A decision is required in non-interactive mode: $prompt"
    exit 1
  fi

  read -r -p "$prompt" choice
  choice="${choice:-$default_choice}"
  printf '%s' "$choice"
}

confirm_yes_no() {
  local question="$1"
  local default_choice="${2:-n}"
  local prompt_default="n"
  local answer

  case "${default_choice,,}" in
    y|yes) prompt_default="y" ;;
    *) prompt_default="n" ;;
  esac

  answer="$(choose_option "$question [y/${prompt_default}]: " "$prompt_default")"
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

read_optional_value() {
  local prompt_text="$1"
  local current_value="${2:-}"
  local input=""

  if [ -n "$current_value" ]; then
    printf '%s' "$current_value"
    return 0
  fi

  if [ "${NON_INTERACTIVE:-false}" = true ]; then
    printf ''
    return 0
  fi

  read -r -p "$prompt_text" input
  printf '%s' "$input"
}
