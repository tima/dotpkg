#!/usr/bin/env bash
# Thin wrappers around gum that fall back to plain read/cat when gum is absent.
# Non-interactive detection: if stdin is not a tty and gum is absent, use safe defaults.

_gum_input() {
  local prompt="$1" default="${2:-}"
  if type -P gum &>/dev/null; then
    gum input --prompt "$prompt" --value "$default"
    return
  fi
  if [[ ! -t 0 ]]; then
    echo "$default"
    return
  fi
  local reply
  IFS= read -r -p "$prompt" reply </dev/tty
  echo "${reply:-$default}"
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
  if type -P gum &>/dev/null; then
    gum pager
    return
  fi
  command -v less &>/dev/null && { less; return; }
  cat
}
