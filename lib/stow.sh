#!/usr/bin/env bash
# GNU Stow wrappers
stow_check() {
  local bundle_dir="$1" target="${2:-$HOME}"

  # HIGH-8: Reject bundles containing symlinks in stow/
  if [[ -d "$bundle_dir/stow" ]]; then
    local symlinks
    symlinks=$(find "$bundle_dir/stow" -type l 2>/dev/null)
    if [[ -n "$symlinks" ]]; then
      echo "dotpkg: bundle contains symlinks in stow/ (security risk):" >&2
      printf '%s\n' "$symlinks" >&2
      return 1
    fi
  fi

  local output conflicts
  output=$(stow --dir="$bundle_dir" --target="$target" -n -v stow 2>&1) || true
  conflicts=$(printf '%s\n' "$output" | grep -i 'CONFLICT\|existing target' || true)
  if [[ -n "$conflicts" ]]; then
    echo "dotpkg: stow conflicts in $(basename "$bundle_dir"):" >&2
    printf '%s\n' "$conflicts" >&2
    return 1
  fi
}

stow_apply() {
  local bundle_dir="$1" target="${2:-$HOME}"
  stow --dir="$bundle_dir" --target="$target" stow
}
