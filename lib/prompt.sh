#!/usr/bin/env bash
# Gum wrappers with fallback

_gum_input() {
  local prompt="$1" default="${2:-}"
  if type -P gum &>/dev/null; then
    gum input --prompt "$prompt" --value "$default"
  elif [[ ! -t 0 ]]; then
    echo "$default"
  else
    local reply
    IFS= read -r -p "$prompt" reply </dev/tty
    echo "${reply:-$default}"
  fi
}

_gum_confirm() {
  local message="$1"
  if type -P gum &>/dev/null; then
    gum confirm "$message"
    return
  fi
  if [[ ! -t 0 ]]; then
    echo "dotpkg: non-interactive, defaulting to no: $message" >&2
    return 1
  fi
  local reply
  IFS= read -r -p "$message [y/N]: " reply </dev/tty
  [[ "$reply" =~ ^[Yy] ]]
}

_gum_pager() {
  type -P gum &>/dev/null && gum pager || ${PAGER:-less}
}
