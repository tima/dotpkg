#!/usr/bin/env bash
# GNU Stow wrappers for bundle config management
# All functions take (bundle_dir, target) where bundle_dir contains a stow/ subdir

# stow_check: dry-run to detect conflicts before applying. Returns 1 if conflicts found.
stow_check() {
  local bundle_dir="$1" target="${2:-$HOME}"
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

stow_remove() {
  local bundle_dir="$1" target="${2:-$HOME}"
  stow --dir="$bundle_dir" --target="$target" --delete stow
}
