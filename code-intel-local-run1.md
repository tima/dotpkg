# dotpkg — Code Intelligence Report

**Objective:** How does bundle installation work — what steps does `dotpkg install` execute, in what order, and how does it handle Brewfile, stow/, extensions.txt, and defaults.sh?  
**Repository:** /Users/tappnel/projects/dotpkg

---

## Executive Summary

There is no `dotpkg install` command. The install operation is `dotpkg add <bundle>`, which calls `install_bundle()` in `lib/bundle.sh`. That function runs six ordered steps per bundle: resolve dependencies, run Brewfile, apply stow, source defaults.sh (local-only), install editor extensions, and copy themes. Steps are skipped if the corresponding file/directory is absent.

---

## Code Architecture

Entry point: `/Users/tappnel/projects/dotpkg/dotpkg` (bash script, `set -euo pipefail`)  
Library files sourced at startup (line 14): all `~/.dotpkg/lib/*.sh`  
Key libs:
- `lib/bundle.sh` — `install_bundle()`, `resolve_bundle()`, dependency traversal, `install_extensions()`
- `lib/stow.sh` — `stow_check()` (dry-run conflict check), `stow_apply()` (live symlink)
- `lib/helpers.sh` — `dotpkg_preset()`, `dotpkg_dock()`, `dotpkg_wallpaper()`, etc. (called by defaults.sh scripts)
- `lib/state.sh` — state.json read/write via inline python3
- `lib/prompt.sh` — gum wrappers for interactive prompts

Dispatch table (`dotpkg` lines 419-436): `add` -> `cmd_add()`, `init` -> `cmd_init()`, `sync` -> `cmd_sync()`. No `install` case exists.

---

## Answer to Your Question

### Command entry point

`dotpkg add <bundle>` calls `cmd_add()` (`dotpkg` lines 76-100):
1. Calls `state_init` — creates `~/.dotpkg/state.json` if missing
2. If a root bundle (`$DOTFILES_DIR/bundle.info`) exists and is not yet installed, installs it first via `install_bundle "$DOTFILES_DIR" "local"`
3. Calls `resolve_bundle()` to find the bundle directory (resolution order: root bundle -> local `bundles/` -> `profiles/` -> trusted `~/.dotpkg/sources` -> GitHub shorthand clone)
4. Calls `install_bundle "$bundle_dir" "$bundle_source"`

### install_bundle() step order

`lib/bundle.sh` lines 168-255. All steps conditional on file/dir presence.

**Step 0: Validation + visited-set (lines 171-188)**  
- Aborts if `bundle.info` missing or `name` field empty  
- Checks `_DOTPKG_VISITED` colon-delimited string; if name already present, prints "(already processed)" and returns 0 (handles diamond dependencies and cycles)  
- Marks name visited

**Step 1: Dependencies — `requires.txt` (lines 193-203)**  
- Reads each non-comment line as a bundle name  
- Calls `resolve_bundle()` on it; aborts if not found  
- Recursively calls `install_bundle()` — deps install before the parent  
- Visited-set prevents infinite loops

**Step 2: Brewfile (lines 206-209)**  
- Runs: `brew bundle --file="$bundle_dir/Brewfile" --no-upgrade`  
- `--no-upgrade`: installs missing packages only; never upgrades existing ones  
- No other flags; brew prints its own output

**Step 3: stow/ (lines 212-222)**  
- Reads `stow_target` from `bundle.info` (default: `$HOME`)  
- Runs `stow_check()` first: `stow --dir="$bundle_dir" --target="$target" -n -v stow` (dry run, verbose)  
  - Greps output for "CONFLICT" or "existing target"  
  - Returns 1 (and aborts install via `set -e`) if conflicts found — no symlinks are created  
- Runs `stow_apply()`: `stow --dir="$bundle_dir" --target="$target" stow` (live, not dry-run)  
  - Creates symlinks for all paths under `bundle_dir/stow/` into `$target`  
- Records stow package names into `stow_paths` variable (for state.json)

**Step 4: defaults.sh (lines 225-233)**  
- Only sourced (`. "$bundle_dir/defaults.sh"`) when `source == "local"`  
- Remote bundles (GitHub shorthand) skip it entirely; prints a warning to stderr  
- Sourced in the current shell so it can call `dotpkg_preset`, `dotpkg_dock`, `dotpkg_wallpaper`, `dotpkg_hotkey_disable`, etc. from `lib/helpers.sh`  
- `dotpkg_preset` also writes to state.json via `state_add_preset()`

**Step 5: extensions.txt (lines 236-239)**  
- Calls `install_extensions "$bundle_dir/extensions.txt"`  
- Detects available editors in order: `code`, `cursor`, `codium` (any/all that exist in PATH)  
- If no editor found, prints "no compatible editor found — skipping extensions" and returns 0  
- For each non-comment line: runs `<editor> --install-extension <ext> --force` for every detected editor  
- On error: if output matches "not found/not exist/unavailable/not be found", warns and continues; other errors abort

**Step 6: themes/ (lines 242-251)**  
- Reads `theme_target` from `bundle.info`  
- If `theme_target` is set: `mkdir -p "$theme_target"` then `cp -r "$bundle_dir/themes/." "$theme_target/"` (unconditional overwrite, idempotent by design)  
- If `theme_target` is absent from `bundle.info`, themes/ is silently skipped even if the directory exists

**Step 7: State write (line 253)**  
- `state_add_bundle "$name" "$source" "$stow_paths"` — appends to `installed_bundles` array in state.json only if name not already present (deduplication guard in python3 inline script)

### Source flag behavior

`source` is passed as the second argument to `install_bundle`. It is either `"local"` or `"github"`. The `"local"` value is hardcoded in `cmd_add` when the bundle name contains no `/`; `"github"` is set when name is a user/repo shorthand. Source is propagated to recursive dependency installs unchanged.

---

## Extension/Integration Points

- Add a new install step: extend `install_bundle()` in `lib/bundle.sh` after step 5; add a new sentinel file pattern to the bundle directory
- Add a preset category: add a `_preset_<name>()` function in `lib/helpers.sh` and add a case branch in `dotpkg_preset()`
- Add a new bundle source: extend `resolve_bundle()` in `lib/bundle.sh` with a new resolution step after the sources check
- Machine-local overrides for presets: place `~/.dotpkg/presets/<category>.local.sh`; sourced automatically after each `dotpkg_preset` call
- Trusted source repos: add GitHub or git URLs to `~/.dotpkg/sources` (one per line); these skip the interactive preview required for raw GitHub shorthand installs

---

## Code Reading Guide

1. `dotpkg` (main script) — dispatch table and `cmd_add()`/`cmd_init()` for the install entry paths
2. `lib/bundle.sh:install_bundle()` (lines 168-255) — canonical step order
3. `lib/bundle.sh:resolve_bundle()` (lines 44-91) — how bundle names become directory paths
4. `lib/stow.sh` — stow_check/stow_apply wrappers (short, read in full)
5. `lib/state.sh` — state.json schema and update logic
6. `lib/helpers.sh` — preset and utility functions available to defaults.sh scripts

---

## Strengths & Weaknesses

| Strengths | Weaknesses |
|-----------|------------|
| Visited-set prevents circular deps and diamond-dep re-execution without requiring a full dep graph | `stow_check` failure aborts the entire install (via `set -e`); no partial rollback or cleanup of already-completed steps |
| `defaults.sh` remote-block is enforced by `source` parameter, not trust flag — no way for a malicious bundle to opt in | Theme step silently skips if `theme_target` missing from `bundle.info`, even when `themes/` exists — silent misconfiguration |
| `brew bundle --no-upgrade` prevents unintended upgrades during repeated sync | `state_add_bundle` deduplication only checks name; re-installing a bundle after source change (local->github) does not update the state record |
| Dependency order guaranteed: deps always complete before parent, not interleaved | No rollback or uninstall command — stow links can be orphaned if a bundle is manually removed from disk |

---

Claude Code | Model: claude-sonnet-4-6 | Start: Aug-05-2026 05:22:59 UTC | Finish: Aug-05-2026 05:24:03 UTC
