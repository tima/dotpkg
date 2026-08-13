#!/usr/bin/env bash
# Bundle install, resolution, and dependency traversal

# Visited-set — reset before each top-level install
_DOTPKG_VISITED=""

_bundle_visited() {
  [[ ":${_DOTPKG_VISITED}:" == *":${1}:"* ]]
}

_bundle_visit() {
  _DOTPKG_VISITED="${_DOTPKG_VISITED:+${_DOTPKG_VISITED}:}${1}"
}

bundle_info_get() {
  grep "^${2}=" "${1}/bundle.info" 2>/dev/null | cut -d= -f2-
}

_source_cache_key() {
  local repo="$1"
  repo="${repo%.git}"
  repo="${repo#https://}"
  repo="${repo#http://}"
  repo="${repo#git@}"
  repo="${repo/://}"
  echo "$repo"
}

_validate_git_url() {
  local url="$1"

  # Reject dangerous schemes and path patterns immediately
  case "$url" in
    file://*|git://*|http://*|ftp://*|ssh://*|sftp://*|rsync://*)
      return 1
      ;;
    /*|../*|./*)
      # Reject absolute paths, relative paths with ../ or ./
      return 1
      ;;
  esac

  # Reject URLs with shell metacharacters (command injection prevention)
  if [[ "$url" == *'$'* || "$url" == *'`'* || "$url" == *';'* || "$url" == *'|'* || "$url" == *'&'* || "$url" == *'('* || "$url" == *')'* ]]; then
    return 1
  fi

  # Now check for valid schemes
  case "$url" in
    https://*)
      # https URLs: must have proper structure https://domain[/path]
      # First, verify we have at least domain.something to prevent https:/invalid-url
      if ! [[ "$url" =~ \. ]]; then
        # Domain must contain at least one dot (github.com, etc.) OR be a simple hostname
        # But if no dot, it must be a valid single hostname (alphanumeric+hyphens only)
        [[ "$url" =~ ^https://[a-zA-Z0-9]+(-[a-zA-Z0-9]+)*(/.*)?$ ]] || return 1
      fi

      local domain_part="${url#https://}"
      domain_part="${domain_part%%/*}"  # Extract just the domain:port part

      # Domain must be alphanumeric with dots and hyphens, but not start/end with dot or hyphen
      if ! [[ "$domain_part" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        # Also allow single char or with optional :port
        [[ "$domain_part" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?:[0-9]+$ ]] || [[ "$domain_part" =~ ^[a-zA-Z0-9]:[0-9]+$ ]] || return 1
      fi

      # Path (if present) can only contain alphanumerics, slash, hyphen, underscore, dot
      local path_part="${url#https://$domain_part}"
      if [[ -n "$path_part" ]]; then
        [[ "$path_part" =~ ^/[a-zA-Z0-9._/-]*$ ]] || return 1
      fi

      return 0
      ;;
    git@*)
      # SSH format: git@host:user/repo
      [[ "$url" =~ ^git@[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]:[a-zA-Z0-9._/-]+$ ]] && return 0
      [[ "$url" =~ ^git@[a-zA-Z0-9]:[a-zA-Z0-9._/-]+$ ]] && return 0  # single char domain
      return 1
      ;;
    [a-zA-Z0-9._-]*/[a-zA-Z0-9._-]*)
      # Plain user/repo shorthand (will be normalized to github.com)
      # GitHub usernames can contain dots, but we reject URLs that look like bare domains
      # Reject if contains :// or .. or ./ or looks like a malformed scheme
      [[ "$url" == *://* || "$url" == *..* || "$url" == *./* ]] && return 1
      # Reject if looks like a scheme (contains : before the slash, e.g., https:/)
      [[ "$url" == *:/* ]] && return 1

      # Reject bare domains like attacker.com/repo
      # If user part looks like a domain (ends with known TLD), reject it
      local user_part="${url%%/*}"
      case "$user_part" in
        *.com|*.org|*.net|*.edu|*.gov|*.io|*.co|*.uk|*.de|*.fr|*.ru|*.cn|*.in|*.au|*.jp|*.br|*.mx|*.ca|*.tv|*.info|*.us)
          return 1
          ;;
      esac
      return 0
      ;;
    *)
      # Reject anything else
      return 1
      ;;
  esac
}

_validate_target_path() {
  local path="$1" for_remote="${2:-false}"

  # Reject explicit path traversal patterns (.. and ./)
  if [[ "$path" == *"../"* ]] || [[ "$path" == *"/.."* ]] || [[ "$path" == *"/./"* ]]; then
    return 1
  fi

  # For remote bundles, restrict to $HOME
  if [[ "$for_remote" == "true" ]]; then
    # Expand tilde to actual home path
    local expanded_path="${path/#\~/$HOME}"

    # After expansion, must be under $HOME or equal to $HOME
    if [[ "$expanded_path" == "$HOME" ]] || [[ "$expanded_path" == "$HOME"/* ]]; then
      return 0
    else
      # Outside $HOME
      return 1
    fi
  fi

  return 0
}

_clone_source() {
  local repo="$1" cache_dir="$2"
  local url
  # Plain user/repo → add github.com prefix
  if [[ "$repo" =~ ^[^/@:\ ]+/[^/@:\ ]+$ ]]; then
    url="https://github.com/${repo}.git"
  else
    url="$repo"
  fi

  # Validate URL before attempting clone
  if ! _validate_git_url "$url"; then
    echo "dotpkg: invalid or unsafe git URL (only https://, git@, or user/repo allowed): $repo" >&2
    return 1
  fi

  echo "dotpkg: cloning source: $repo..."
  mkdir -p "$(dirname "$cache_dir")"
  git clone --quiet "$url" "$cache_dir"
}

# Resolution order: local bundles/ -> profiles/ -> sources -> GitHub shorthand
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

# ponytail: GitHub shorthand requires preview; sources are trusted
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

install_extensions() {
  local bundle_dir="$1"
  local editors=()

  for _ed in code cursor codium; do command -v "$_ed" &>/dev/null && editors+=("$_ed"); done

  if [[ ${#editors[@]} -eq 0 ]]; then
    echo "  no compatible editor found — skipping extensions"
    return 0
  fi

  local err_file
  err_file=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$err_file'" RETURN

  local editor
  for editor in "${editors[@]}"; do
    local ext_file
    local map_name="$editor"
    [[ "$editor" == "code" ]] && map_name="vscode"
    ext_file="$bundle_dir/extensions.${map_name}.txt"
    [[ ! -f "$ext_file" ]] && ext_file="$bundle_dir/extensions.txt"
    [[ ! -f "$ext_file" ]] && continue

    while IFS= read -r ext; do
      [[ -z "$ext" || "$ext" == \#* ]] && continue
      if ! "$editor" --install-extension "$ext" --force >"$err_file" 2>&1; then
        if grep -qi "not found\|not exist\|unavailable\|not be found" "$err_file"; then
          echo "  warning: extension unavailable in $editor (skipping): $ext" >&2
        else
          echo "dotpkg: extension install error in $editor: $ext" >&2
          cat "$err_file" >&2
          return 1
        fi
      fi
    done < "$ext_file"
  done
}

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
    local dep dep_dir dep_source
    while IFS= read -r dep; do
      [[ -z "$dep" || "$dep" == \#* ]] && continue
      if ! dep_dir=$(resolve_bundle "$dep"); then
        echo "dotpkg: dependency not found: $dep (required by $name)" >&2
        return 1
      fi

      # Re-evaluate dependency's actual source based on resolved location
      if [[ "$dep_dir" == "$DOTFILES_DIR"* ]]; then
        # Resolved to local bundle or profile (under DOTFILES_DIR)
        dep_source="local"
      else
        # Resolved via sources cache or GitHub — treat as remote
        dep_source="remote"
      fi

      install_bundle "$dep_dir" "$dep_source"
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
    stow_target=$(bundle_info_get "$bundle_dir" stow_target 2>/dev/null || true)
    stow_target="${stow_target:-$HOME}"
    stow_target="${stow_target/#\~/$HOME}"

    # For remote bundles, validate stow_target path
    if [[ "$source" == "remote" ]]; then
      if ! _validate_target_path "$stow_target" "true"; then
        echo "dotpkg: stow_target must be under \$HOME for remote bundles" >&2
        echo "         Invalid: $stow_target" >&2
        return 1
      fi
    fi

    echo "  [stow] linking configs -> $stow_target..."
    stow_check "$bundle_dir" "$stow_target" || return 1
    stow_apply "$bundle_dir" "$stow_target"
    stow_paths=$(find "$bundle_dir/stow" -maxdepth 1 -mindepth 1 -exec basename {} \; 2>/dev/null | tr '\n' ' ')
  fi

  # 4. defaults.sh — personal bundles only (remote bundles cannot execute code)
  if [[ -f "$bundle_dir/defaults.sh" ]]; then
    if [[ "$source" == "local" ]]; then
      echo "  [defaults] applying presets..."
      # shellcheck disable=SC1090
      . "$bundle_dir/defaults.sh"
    else
      echo "  [defaults] skipped (remote bundle) — see bundle README for manual setup" >&2
    fi
  fi

  # 5. Editor extensions (per-editor or generic)
  if [[ -f "$bundle_dir/extensions.txt" ]] || [[ -f "$bundle_dir/extensions.vscode.txt" ]] || [[ -f "$bundle_dir/extensions.cursor.txt" ]] || [[ -f "$bundle_dir/extensions.codium.txt" ]]; then
    echo "  [extensions] installing..."
    install_extensions "$bundle_dir"
  fi

  # 6. Themes — always re-copy unconditionally (idempotent by design)
  if [[ -d "$bundle_dir/themes" ]]; then
    local theme_target
    theme_target=$(bundle_info_get "$bundle_dir" theme_target 2>/dev/null || true)
    if [[ -n "$theme_target" ]]; then
      # For remote bundles, validate theme_target path
      if [[ "$source" == "remote" ]]; then
        if ! _validate_target_path "$theme_target" "true"; then
          echo "dotpkg: theme_target must be under \$HOME for remote bundles" >&2
          echo "         Invalid: $theme_target" >&2
          return 1
        fi
      fi

      theme_target="${theme_target/#\~/$HOME}"
      mkdir -p "$theme_target"
      cp -r "$bundle_dir/themes/." "$theme_target/"
      echo "  [themes] copied -> $theme_target"
    fi
  fi

  state_add_bundle "$name" "$source" "$stow_paths"
  echo "  done: $name"
}
