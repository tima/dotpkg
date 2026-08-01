#!/usr/bin/env bash
# Bundle install, resolution, and dependency traversal.
# Requires: DOTPKG_HOME, DOTFILES_DIR, state.sh, stow.sh, helpers.sh sourced by caller.

# ---------------------------------------------------------------------------
# Visited-set — global string of colon-separated bundle names.
# Reset (_DOTPKG_VISITED="") before each top-level install call.
# ---------------------------------------------------------------------------
_DOTPKG_VISITED=""

_bundle_visited() {
  [[ ":${_DOTPKG_VISITED}:" == *":${1}:"* ]]
}

_bundle_visit() {
  _DOTPKG_VISITED="${_DOTPKG_VISITED:+${_DOTPKG_VISITED}:}${1}"
}

# ---------------------------------------------------------------------------
# bundle_info_get <bundle_dir> <key> — read a key from bundle.info
# ---------------------------------------------------------------------------
bundle_info_get() {
  grep "^${2}=" "${1}/bundle.info" 2>/dev/null | cut -d= -f2-
}

# ---------------------------------------------------------------------------
# _source_cache_key <repo-spec> — normalize a source repo spec to a cache path key.
# Handles: user/repo, https://host/path, git@host:org/repo.git
# ---------------------------------------------------------------------------
_source_cache_key() {
  local repo="$1"
  repo="${repo%.git}"          # strip .git suffix
  repo="${repo#https://}"      # strip https://
  repo="${repo#http://}"       # strip http://
  repo="${repo#git@}"          # strip git@
  repo="${repo/://}"           # git@host:org/repo -> host/org/repo (replace first : with /)
  echo "$repo"
}

# ---------------------------------------------------------------------------
# _clone_source <repo-spec> <cache_dir> — clone a source repo (no preview, trusted).
# ---------------------------------------------------------------------------
_clone_source() {
  local repo="$1" cache_dir="$2"
  local url
  # Plain user/repo → add github.com prefix
  if [[ "$repo" =~ ^[^/@:\ ]+/[^/@:\ ]+$ ]]; then
    url="https://github.com/${repo}.git"
  else
    url="$repo"
  fi
  echo "dotpkg: cloning source: $repo..."
  mkdir -p "$(dirname "$cache_dir")"
  git clone --quiet "$url" "$cache_dir"
}

# ---------------------------------------------------------------------------
# resolve_bundle <name> — returns absolute path to the bundle directory.
# Resolution order (per spec): local bundles/ -> profiles/ -> sources -> GitHub shorthand.
# ---------------------------------------------------------------------------
resolve_bundle() {
  local name="$1"

  # 0. Root bundle — DOTFILES_DIR itself (not in bundles/ subdir)
  if [[ -f "$DOTFILES_DIR/bundle.info" ]]; then
    local _root_name
    _root_name=$(grep "^name=" "$DOTFILES_DIR/bundle.info" 2>/dev/null | cut -d= -f2-)
    [[ "$name" == "$_root_name" ]] && { echo "$DOTFILES_DIR"; return; }
  fi

  # 1. Local bundle
  local local_path="$DOTFILES_DIR/bundles/$name"
  [[ -d "$local_path" && -f "$local_path/bundle.info" ]] && { echo "$local_path"; return; }

  # 2. Profile
  local profile_path="$DOTFILES_DIR/profiles/$name"
  [[ -d "$profile_path" && -f "$profile_path/bundle.info" ]] && { echo "$profile_path"; return; }

  # 3. Sources: trusted repos registered in ~/.dotpkg/sources (checked before GitHub shorthand)
  if [[ -f "$DOTPKG_HOME/sources" ]]; then
    local repo source_key source_cache
    while IFS= read -r repo; do
      [[ -z "$repo" || "$repo" == \#* ]] && continue
      source_key=$(_source_cache_key "$repo")
      source_cache="$DOTPKG_HOME/cache/sources/$source_key"
      if [[ ! -d "$source_cache" ]]; then
        _clone_source "$repo" "$source_cache" || continue
      fi
      if [[ -d "$source_cache/bundles/$name" && -f "$source_cache/bundles/$name/bundle.info" ]]; then
        echo "$source_cache/bundles/$name"
        return
      fi
    done < "$DOTPKG_HOME/sources"
  fi

  # 4. GitHub shorthand (user/repo) — single-bundle repo, full preview required
  if [[ "$name" == */* ]]; then
    local cache_dir="$DOTPKG_HOME/cache/github/$name"
    if [[ ! -d "$cache_dir" ]]; then
      _fetch_github_bundle "$name" "$cache_dir" || return 1
    fi
    echo "$cache_dir"
    return
  fi

  echo "dotpkg: bundle not found: $name" >&2
  return 1
}

# ---------------------------------------------------------------------------
# _fetch_github_bundle <user/repo> <cache_dir>
# Shows full preview, requires explicit y confirmation, then caches.
# Trust model: ADR-0003 — GitHub shorthand requires preview; sources are trusted.
# ---------------------------------------------------------------------------
_fetch_github_bundle() {
  local shorthand="$1" cache_dir="$2"
  local url="https://github.com/${shorthand}.git"
  local tmp_dir

  echo "dotpkg: fetching ${shorthand}..."
  tmp_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp_dir'" RETURN

  if ! git clone --depth=1 --quiet "$url" "$tmp_dir" 2>/dev/null; then
    echo "dotpkg: failed to clone: $url" >&2
    return 1
  fi

  if [[ ! -f "$tmp_dir/bundle.info" ]]; then
    echo "dotpkg: no bundle.info at root of $shorthand — not a dotpkg bundle" >&2
    return 1
  fi

  # Preview all bundle files before any confirmation
  echo ""
  echo "=== Bundle preview: $shorthand ==="
  local f
  for f in bundle.info Brewfile defaults.sh extensions.txt requires.txt; do
    [[ -f "$tmp_dir/$f" ]] || continue
    echo ""
    echo "--- $f ---"
    cat "$tmp_dir/$f"
  done
  echo ""

  if ! _gum_confirm "Install bundle $shorthand?"; then
    echo "dotpkg: aborted" >&2
    return 1
  fi

  mkdir -p "$(dirname "$cache_dir")"
  cp -r "$tmp_dir" "$cache_dir"
}

# ---------------------------------------------------------------------------
# install_extensions <extensions_txt>
# Installs editor extensions; unavailable = warn+continue, other errors = abort.
# ---------------------------------------------------------------------------
install_extensions() {
  local ext_file="$1"
  local editors=()

  command -v code   &>/dev/null && editors+=(code)
  command -v cursor &>/dev/null && editors+=(cursor)
  command -v codium &>/dev/null && editors+=(codium)

  if [[ ${#editors[@]} -eq 0 ]]; then
    echo "  no compatible editor found — skipping extensions"
    return 0
  fi

  local ext err_file
  err_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$err_file'" RETURN

  while IFS= read -r ext; do
    [[ -z "$ext" || "$ext" == \#* ]] && continue
    local editor
    for editor in "${editors[@]}"; do
      if ! "$editor" --install-extension "$ext" --force >"$err_file" 2>&1; then
        if grep -qi "not found\|not exist\|unavailable\|not be found" "$err_file"; then
          echo "  warning: extension unavailable (skipping): $ext" >&2
        else
          echo "dotpkg: extension install error: $ext" >&2
          cat "$err_file" >&2
          return 1
        fi
      fi
    done
  done < "$ext_file"
}

# ---------------------------------------------------------------------------
# install_bundle <bundle_dir> [source]
# Core install: deps -> Brewfile -> stow -> defaults.sh -> extensions -> themes.
# ---------------------------------------------------------------------------
install_bundle() {
  local bundle_dir="$1" source="${2:-local}"

  if [[ ! -f "$bundle_dir/bundle.info" ]]; then
    echo "dotpkg: no bundle.info in $bundle_dir" >&2
    return 1
  fi

  local name
  name=$(bundle_info_get "$bundle_dir" name)
  if [[ -z "$name" ]]; then
    echo "dotpkg: bundle.info missing 'name' field in $bundle_dir" >&2
    return 1
  fi

  # Visited-set: skip duplicates (handles cycles and diamond deps)
  if _bundle_visited "$name"; then
    echo "dotpkg: (already processed: $name)"
    return 0
  fi
  _bundle_visit "$name"

  echo "dotpkg: installing $name..."

  # 1. Dependencies (visited-set prevents cycles)
  if [[ -f "$bundle_dir/requires.txt" ]]; then
    local dep dep_dir
    while IFS= read -r dep; do
      [[ -z "$dep" || "$dep" == \#* ]] && continue
      if ! dep_dir=$(resolve_bundle "$dep"); then
        echo "dotpkg: dependency not found: $dep (required by $name)" >&2
        return 1
      fi
      install_bundle "$dep_dir" "$source"
    done < "$bundle_dir/requires.txt"
  fi

  # 2. Brewfile — adds missing, never upgrades
  if [[ -f "$bundle_dir/Brewfile" ]]; then
    echo "  [brew] installing packages..."
    brew bundle --file="$bundle_dir/Brewfile" --no-upgrade
  fi

  # 3. Stow — conflict check then apply
  local stow_paths=""
  if [[ -d "$bundle_dir/stow" ]]; then
    local stow_target
    stow_target=$(bundle_info_get "$bundle_dir" stow_target)
    stow_target="${stow_target:-$HOME}"
    stow_target="${stow_target/#\~/$HOME}"
    echo "  [stow] linking configs -> $stow_target..."
    stow_check "$bundle_dir" "$stow_target"
    stow_apply "$bundle_dir" "$stow_target"
    stow_paths=$(find "$bundle_dir/stow" -maxdepth 1 -mindepth 1 -exec basename {} \; 2>/dev/null | tr '\n' ' ')
  fi

  # 4. defaults.sh — sourced with fail-fast (set -e propagates from parent)
  if [[ -f "$bundle_dir/defaults.sh" ]]; then
    echo "  [defaults] applying presets..."
    # shellcheck disable=SC1090
    . "$bundle_dir/defaults.sh"
  fi

  # 5. Editor extensions
  if [[ -f "$bundle_dir/extensions.txt" ]]; then
    echo "  [extensions] installing..."
    install_extensions "$bundle_dir/extensions.txt"
  fi

  # 6. Themes — always re-copy unconditionally (idempotent by design)
  if [[ -d "$bundle_dir/themes" ]]; then
    local theme_target
    theme_target=$(bundle_info_get "$bundle_dir" theme_target)
    if [[ -n "$theme_target" ]]; then
      theme_target="${theme_target/#\~/$HOME}"
      mkdir -p "$theme_target"
      cp -r "$bundle_dir/themes/." "$theme_target/"
      echo "  [themes] copied -> $theme_target"
    fi
  fi

  state_add_bundle "$name" "$source" "$stow_paths"
  echo "  done: $name"
}
