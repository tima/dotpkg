# dotpkg — Code Intelligence Report

**Objective:** How does bundle source resolution work — how does dotpkg determine whether a bundle is local or from GitHub, clone remote bundles, and what path does a spec like `user/repo` follow to become an installed bundle directory?
**Repository:** /Users/tappnel/projects/dotpkg

---

## Executive Summary

`resolve_bundle()` in `lib/bundle.sh` is the single resolution function. It walks four tiers in order (root bundle, local `bundles/`, local `profiles/`, registered sources, then GitHub shorthand) and returns a filesystem path. The `user/repo` detection is a pattern match on `/` presence; matching triggers `_fetch_github_bundle()`, which clones to a temp dir, shows a mandatory security preview, prompts for confirmation, then copies to `~/.dotpkg/cache/github/<user>/<repo>`. That path is what `install_bundle()` operates on.

---

## Code Architecture

Entry point: `dotpkg` (root script). Dispatches by `$1` to `cmd_*` functions defined in the same file. Library functions are loaded via a glob at startup:

```
for _lib in "$DOTPKG_HOME/lib"/*.sh; do . "$_lib"; done
```

Key lib files:

| File | Role |
|---|---|
| `lib/bundle.sh` | `resolve_bundle`, `_fetch_github_bundle`, `_clone_source`, `install_bundle`, visited-set |
| `lib/state.sh` | JSON state read/write via embedded python3 |
| `lib/helpers.sh` | macOS preset helpers (`dotpkg_preset`, `dotpkg_dock`, etc.) |
| `lib/stow.sh` | Stow conflict check and apply |
| `lib/prompt.sh` | `_gum_confirm`, `_gum_input` wrappers |

The `cmd_add` handler is the only command that calls `resolve_bundle` with user input. `cmd_sync` re-installs all state-tracked bundles but always calls `install_bundle` with source label `"local"` regardless of original source.

---

## Answer to Your Question

### Step 1: Is the spec local or GitHub?

**`dotpkg add user/repo`** enters `cmd_add` in `dotpkg` (line 76–100).

The source label is set at line 97:
```sh
[[ "$bundle_name" == */* ]] && bundle_source="github" || bundle_source="local"
```

`user/repo` contains `/`, so `bundle_source="github"`.

### Step 2: resolve_bundle() — the four-tier waterfall

`lib/bundle.sh:44`, function `resolve_bundle()`:

**Tier 0 — Root bundle** (line 47–51): Reads `$DOTFILES_DIR/bundle.info`. If the `name=` field matches, returns `$DOTFILES_DIR` immediately.

**Tier 1 — Local bundle** (line 54–56): Checks `$DOTFILES_DIR/bundles/<name>/bundle.info`. If present, returns that path.

**Tier 2 — Profile** (line 58–60): Checks `$DOTFILES_DIR/profiles/<name>/bundle.info`. If present, returns that path.

**Tier 3 — Registered sources** (line 62–77): Reads `~/.dotpkg/sources` line-by-line. For each registered repo, computes a cache key via `_source_cache_key()` (strips protocol/`.git`, normalizes `git@github.com:` to `github.com/`), then looks for `$DOTPKG_HOME/cache/sources/<key>/bundles/<name>/bundle.info`. If the source isn't cloned yet, calls `_clone_source()` to clone it first. This tier is **trusted** — no preview required.

**Tier 4 — GitHub shorthand** (line 79–87): Triggered only if `$name` contains `/`. Sets `cache_dir="$DOTPKG_HOME/cache/github/$name"` (i.e., `~/.dotpkg/cache/github/user/repo`). If not already cached, calls `_fetch_github_bundle()`.

### Step 3: _fetch_github_bundle() — clone, preview, confirm, cache

`lib/bundle.sh:94–133`, function `_fetch_github_bundle()`:

1. Constructs URL: `https://github.com/${shorthand}.git` (line 96)
2. Clones into a **temp dir** with `--depth=1 --quiet` (line 104)
3. Validates `bundle.info` exists at temp dir root (line 109–112); fails if absent
4. Displays file preview: iterates `bundle.info Brewfile defaults.sh extensions.txt requires.txt` and cats each present file (lines 118–123)
5. Calls `_gum_confirm "Install bundle $shorthand?"` (line 126); returns 1 on refusal
6. `mkdir -p "$(dirname "$cache_dir")"` then `cp -r "$tmp_dir" "$cache_dir"` (lines 131–132)
7. Temp dir is cleaned by a `trap "rm -rf '$tmp_dir'" RETURN` (line 102)

### Step 4: install_bundle() receives the cache path

`cmd_add` calls `install_bundle "$bundle_dir" "$bundle_source"` (line 99) where:
- `$bundle_dir` = `~/.dotpkg/cache/github/user/repo`
- `$bundle_source` = `"github"`

`lib/bundle.sh:168`, function `install_bundle()`:

Execution order inside `install_bundle`:
1. Checks `bundle.info` exists, reads `name=`
2. Skips if already in `_DOTPKG_VISITED` (cycle/diamond guard)
3. Processes `requires.txt` — calls `resolve_bundle` recursively for each dep, then `install_bundle "$dep_dir" "$source"` (same source label propagates down)
4. Runs `brew bundle --no-upgrade` if `Brewfile` present
5. Runs `stow_check` + `stow_apply` if `stow/` dir present
6. **Skips `defaults.sh`** if `source != "local"` (line 226 check — this is the security gate for remote bundles)
7. Installs editor extensions from `extensions.txt`
8. Copies `themes/` if present and `theme_target` set
9. Calls `state_add_bundle "$name" "$source" "$stow_paths"` — records to `~/.dotpkg/state.json`

### Full path for `dotpkg add user/repo`

```
cmd_add "user/repo"
  bundle_source = "github"          # because "user/repo" contains /
  resolve_bundle "user/repo"
    Tier 0: no name match in DOTFILES_DIR/bundle.info
    Tier 1: DOTFILES_DIR/bundles/user/repo/ does not exist
    Tier 2: DOTFILES_DIR/profiles/user/repo/ does not exist
    Tier 3: no ~/.dotpkg/sources file (or name not found in sources)
    Tier 4: name contains / -> cache_dir = ~/.dotpkg/cache/github/user/repo
      not yet cached -> _fetch_github_bundle "user/repo" "~/.dotpkg/cache/github/user/repo"
        git clone --depth=1 https://github.com/user/repo.git -> $tmp_dir
        validate bundle.info present
        preview all bundle files to stdout
        _gum_confirm -> user approves
        cp -r $tmp_dir ~/.dotpkg/cache/github/user/repo
        trap: rm -rf $tmp_dir
      returns "~/.dotpkg/cache/github/user/repo"
  install_bundle "~/.dotpkg/cache/github/user/repo" "github"
    resolve + install requires.txt deps (if any)
    brew bundle (if Brewfile)
    stow apply (if stow/)
    defaults.sh SKIPPED (source == "github")
    extensions.txt install (if present)
    state_add_bundle "repo-name" "github" ...
```

### Subsequent runs

On `dotpkg add user/repo` a second time: `resolve_bundle` hits Tier 4, finds `~/.dotpkg/cache/github/user/repo` already exists (`-d "$cache_dir"` is true at line 82), skips `_fetch_github_bundle`, and returns the cached path directly.

On `dotpkg update`: `cmd_update` iterates `~/.dotpkg/cache/github/*/*` and calls `git -C "$repo_dir" pull --quiet` for each (line 258), then runs `cmd_sync`.

On `dotpkg sync`: `cmd_sync` calls `resolve_bundle "$name"` for each state-tracked bundle name. For a `user/repo`-originated bundle, the bundle name stored in state is the `name=` field from `bundle.info` (e.g., `"my-bundle"`), not the GitHub shorthand. `resolve_bundle` will find it in Tier 4 only if `name` contains `/` — but the state stores the bundle's declared name, not the shorthand. This means sync re-resolves by declared name through Tiers 0–3. If the declared name matches a local bundle or source, it resolves there; if not found anywhere, it fails silently (`2>/dev/null`) and logs "skipping missing bundle".

---

## Extension/Integration Points

- **Add a new resolution tier**: Insert before the GitHub shorthand block in `resolve_bundle()` (`lib/bundle.sh:79`). Tiers are checked in order; first match wins.
- **Add a new install step**: Insert a block in `install_bundle()` after step 5 (extensions). The `$source` variable is available to gate local-vs-remote behavior.
- **Register a trusted bundle registry**: Add a git URL to `~/.dotpkg/sources`. It is auto-cloned on first `add`/`update` and does not require preview confirmation.
- **Override bundle security**: Change the `[[ "$source" == "local" ]]` guard at `lib/bundle.sh:226`. Currently the only code-execution gate in the install pipeline.

---

## Code Reading Guide

1. `dotpkg` (root) lines 76–100 — `cmd_add`: entry for `add` command, source label assignment
2. `lib/bundle.sh:44–91` — `resolve_bundle`: four-tier waterfall
3. `lib/bundle.sh:94–133` — `_fetch_github_bundle`: clone + preview + confirm + cache
4. `lib/bundle.sh:168–255` — `install_bundle`: sequential install steps, security gate
5. `lib/state.sh` — how bundle records are written to `state.json`
6. `dotpkg` lines 105–123 — `cmd_sync`: how re-installs are driven from state

---

## Strengths & Weaknesses

| Strengths | Weaknesses |
|---|---|
| Mandatory file preview before any GitHub bundle install; user confirmation required — no silent code execution from remote | `cmd_sync` always passes `"local"` as source label (`dotpkg:116`), so a re-synced GitHub bundle has `defaults.sh` executed if it exists — the security gate is bypassed on sync |
| Tier ordering is explicit and documented in comments and `cmd_help`; easy to trace | State stores declared bundle `name`, not the GitHub shorthand; `cmd_sync` cannot re-resolve GitHub-only bundles by shorthand if their declared name is not unique across tiers |
| Visited-set prevents dep cycles and diamond installs | `_clone_source` (Tier 3) uses full clone, not `--depth=1`; `_fetch_github_bundle` (Tier 4) uses `--depth=1` — inconsistent |
| `defaults.sh` execution gated on `source == "local"` — clear security model for remote bundles | No lock file during multi-step install; concurrent `dotpkg add` runs could corrupt state.json |

---

**Analysis note:** ast-grep (`sg`) does not support `sh` as a language and exited with error. All structural searches used `rg`/`grep` as the documented fallback.

---

Claude Code | Sonnet 4.6 | Start: Aug-05-2026 05:43:45 UTC | Finish: Aug-05-2026 05:44:42 UTC
