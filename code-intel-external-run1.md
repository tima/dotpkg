# dotpkg — Code Intelligence Report

**Objective:** How does bundle installation work — what steps does `dotpkg install` execute, in what order, and how does it handle Brewfile, stow/, extensions.txt, and defaults.sh?  
**Repository:** /Users/tappnel/projects/dotpkg

---

## Executive Summary

There is no `dotpkg install` command. Bundle installation is performed by `dotpkg add` (single bundle) or `dotpkg init` (root bundle + optional profile). Both converge on `install_bundle()` in `lib/bundle.sh`, which executes 9 steps in fixed order: dependency resolution -> Brewfile -> stow/ -> defaults.sh -> extensions.txt -> themes/ -> state recording.

---

## Code Architecture

Entry point: `dotpkg` (project root) — a Bash script that sources all `lib/*.sh` files at startup (`dotpkg:14`), then dispatches to `cmd_*` functions.

Lib modules and responsibilities:

| File | Role |
|------|------|
| `lib/bundle.sh` | `install_bundle()`, `resolve_bundle()`, dependency traversal, GitHub fetch |
| `lib/stow.sh` | `stow_check()` (dry-run conflict detection), `stow_apply()` (actual symlink) |
| `lib/state.sh` | JSON state read/write via embedded Python3; `~/.dotpkg/state.json` |
| `lib/helpers.sh` | `dotpkg_preset()`, `dotpkg_dock()`, `dotpkg_wallpaper()`, `dotpkg_terminal_import()`, `dotpkg_hotkey_*()` |
| `lib/prompt.sh` | `gum` wrappers with plain-readline fallback |

Commands that call `install_bundle()`:

- `cmd_init` (`dotpkg:16-71`) — calls `install_bundle "$DOTFILES_DIR" "local"` for root bundle, then `install_bundle "$profile_dir" "local"` for profile if `--profile` given
- `cmd_add` (`dotpkg:76-100`) — calls `install_bundle "$DOTFILES_DIR" "local"` for root bundle (if not yet installed), then `install_bundle "$bundle_dir" "$bundle_source"` for target bundle
- `cmd_sync` (`dotpkg:105-124`) — calls `install_bundle "$bundle_dir" "local"` for each name in state
- `install_bundle` itself — calls `install_bundle` recursively for each entry in `requires.txt`

---

## Answer to Your Question

**There is no `dotpkg install` command.** The dispatch table at `dotpkg:422-436` lists: `init`, `add`, `sync`, `status`, `list`, `update`, `create`, `adopt`, `help`. Unknown commands exit 1. The closest match to "install a bundle" is `dotpkg add <bundle>`, which calls `install_bundle()`.

### install_bundle() — full execution sequence

Defined at `lib/bundle.sh:168-255`. Steps execute in this fixed order:

**Pre-step: Validation**
- Check `bundle.info` exists (`lib/bundle.sh:171-173`). Missing -> print error, return 1.
- Read `name` field from `bundle.info` (`lib/bundle.sh:177-181`). Empty -> print error, return 1.
- Visited-set check (`lib/bundle.sh:183-188`): if `name` already in `$_DOTPKG_VISITED`, print "(already processed)" and return 0. Prevents dependency cycles and diamond-dep re-runs.

**Step 1 — Dependencies (requires.txt)**
- Guard: `[[ -f "$bundle_dir/requires.txt" ]]` (`lib/bundle.sh:193`).
- Reads each non-blank, non-comment line as a dependency name.
- Calls `resolve_bundle "$dep"` for each (`lib/bundle.sh:198`).
- Calls `install_bundle "$dep_dir" "$source"` recursively (`lib/bundle.sh:201`).
- Missing dependency -> print error, return 1.

**Step 2 — Brewfile**
- Guard: `[[ -f "$bundle_dir/Brewfile" ]]` (`lib/bundle.sh:206`).
- Runs: `brew bundle --file="$bundle_dir/Brewfile" --no-upgrade` (`lib/bundle.sh:208`).
- `--no-upgrade` means already-installed packages are not upgraded.
- No conditional on source (local vs remote) — runs for all source types.

**Step 3 — stow/**
- Guard: `[[ -d "$bundle_dir/stow" ]]` (`lib/bundle.sh:213`).
- Reads `stow_target` from `bundle.info` (`lib/bundle.sh:215`). Defaults to `$HOME` if unset (`lib/bundle.sh:216`). Tilde-expands the value (`lib/bundle.sh:217`).
- Sub-step 3a: `stow_check "$bundle_dir" "$stow_target"` (`lib/bundle.sh:219`).
  - Runs `stow --dir="$bundle_dir" --target="$target" -n -v stow` (dry run with verbose) (`lib/stow.sh:6`).
  - Greps output for "CONFLICT" or "existing target" (`lib/stow.sh:8`).
  - On conflict: prints errors to stderr, returns 1 (which propagates up, aborting install).
- Sub-step 3b: `stow_apply "$bundle_dir" "$stow_target"` (`lib/bundle.sh:220`).
  - Runs `stow --dir="$bundle_dir" --target="$target" stow` (`lib/stow.sh:17`). Creates symlinks.
- Collects stow_paths for state: `find "$bundle_dir/stow" -maxdepth 1 -mindepth 1 -exec basename {} \;` (`lib/bundle.sh:221`).
- No conditional on source type — runs for all source types.

**Step 4 — defaults.sh**
- Guard: `[[ -f "$bundle_dir/defaults.sh" ]]` (`lib/bundle.sh:225`).
- **Source guard:** `[[ "$source" == "local" ]]` (`lib/bundle.sh:226`).
  - If source is "local": sources file with `. "$bundle_dir/defaults.sh"` (`lib/bundle.sh:229`). Runs in the current shell, so all `dotpkg_preset`, `dotpkg_dock`, etc. functions are available.
  - If source is NOT "local" (i.e., remote/GitHub): prints warning "skipped (remote bundle) — see bundle README for manual setup" to stderr (`lib/bundle.sh:231`). No execution.
- `dotpkg_preset()` in `lib/helpers.sh:4-33` is the main function called by defaults.sh scripts. It dispatches to category-specific `_preset_*` functions and optionally sources a machine-local override at `~/.dotpkg/presets/<category>.local.sh`.

**Step 5 — extensions.txt**
- Guard: `[[ -f "$bundle_dir/extensions.txt" ]]` (`lib/bundle.sh:237`).
- Calls `install_extensions "$bundle_dir/extensions.txt"` (`lib/bundle.sh:238`).
- `install_extensions()` (`lib/bundle.sh:135-166`):
  - Detects editors in order: `code`, `cursor`, `codium` — adds each found on PATH to an array (`lib/bundle.sh:139`).
  - If no editor found: prints "no compatible editor found — skipping extensions" and returns 0.
  - Reads each non-blank, non-comment line as an extension ID.
  - For each extension ID, loops over every detected editor and runs `"$editor" --install-extension "$ext" --force` (`lib/bundle.sh:155`).
  - On "not found / not exist / unavailable / not be found" error strings: warns and skips the extension (`lib/bundle.sh:157-159`).
  - On other errors: prints error, returns 1 (`lib/bundle.sh:160-162`).
- No conditional on source type — runs for all source types.

**Step 6 — themes/**
- Guard: `[[ -d "$bundle_dir/themes" ]]` (`lib/bundle.sh:243`).
- Reads `theme_target` from `bundle.info` (`lib/bundle.sh:244`).
- **Second guard:** `[[ -n "$theme_target" ]]` (`lib/bundle.sh:245`). If `theme_target` is empty or missing from bundle.info, the themes directory is silently skipped.
- If set: tilde-expands, `mkdir -p "$theme_target"`, then `cp -r "$bundle_dir/themes/." "$theme_target/"` (`lib/bundle.sh:247-249`).

**Post-step: State recording**
- Always runs at end of successful install_bundle() call: `state_add_bundle "$name" "$source" "$stow_paths"` (`lib/bundle.sh:253`).
- `state_add_bundle()` in `lib/state.sh:22-37`: uses embedded Python3 to read/write `~/.dotpkg/state.json`. Only appends if `name` not already present (idempotent). Records: `name`, `source`, `installed_at` (ISO date), `stow_paths` (list of stow package names).

### Source parameter values and their effects

| Invocation path | source value | defaults.sh behavior |
|-----------------|--------------|----------------------|
| `cmd_init`, `cmd_add` (local bundle), `cmd_sync` | "local" | executed |
| `cmd_add` (GitHub shorthand `user/repo`) | "github" | skipped, warning printed |
| `install_bundle` recursive dep calls | inherits caller's source | inherits caller behavior |

### Dependency resolution order (resolve_bundle)

Defined at `lib/bundle.sh:44-91`. Checked in order:

1. Root bundle: `$DOTFILES_DIR` itself (matched by name in `bundle.info`)
2. Local: `$DOTFILES_DIR/bundles/<name>/`
3. Profile: `$DOTFILES_DIR/profiles/<name>/`
4. Sources: repos listed in `~/.dotpkg/sources` (trusted — cloned on demand, no preview)
5. GitHub shorthand (`user/repo`): cloned to `~/.dotpkg/cache/github/<user>/<repo>/` after interactive preview and confirmation

---

## Extension/Integration Points

- **Add a new preset category:** Add a `_preset_<category>()` function in `lib/helpers.sh` and a matching `case` entry in `dotpkg_preset()` (`lib/helpers.sh:9-21`). No other files to modify.

- **Override a preset for a specific machine:** Create `~/.dotpkg/presets/<category>.local.sh`. It is sourced after the preset runs (`lib/helpers.sh:24-28`). No dotpkg code changes needed.

- **Add a new editor to extensions.txt support:** Add the editor binary name to the `for _ed in ...` line in `install_extensions()` (`lib/bundle.sh:139`).

- **Control stow target per bundle:** Set `stow_target=<path>` in the bundle's `bundle.info`. Read at `lib/bundle.sh:215`.

- **Control theme copy destination:** Set `theme_target=<path>` in `bundle.info`. Without this field, themes/ is silently skipped.

- **Add a new top-level command:** Add a `cmd_<name>()` function in `dotpkg` and a `case` entry in the dispatch block at `dotpkg:422`.

Files identified by tracing; exhaustive directory scan not performed — additional commands may exist.

---

## Code Reading Guide

1. Start with `dotpkg` (project root): understand CLI dispatch, env var setup, lib sourcing
2. Read `lib/bundle.sh`: the core `install_bundle()` and `resolve_bundle()` functions — this is where all installation logic lives
3. Read `lib/stow.sh`: two functions only; understand the dry-run/apply split
4. Read `lib/helpers.sh`: understand what defaults.sh scripts can call (`dotpkg_preset`, `dotpkg_dock`, `dotpkg_wallpaper`, `dotpkg_hotkey_*`)
5. Read `lib/state.sh`: understand how install state is persisted (JSON via embedded Python3)
6. Read `lib/prompt.sh` last: gum wrappers with fallback, used only during interactive flows

---

## Strengths & Weaknesses

| Strengths | Weaknesses |
|-----------|------------|
| Dependency cycle prevention via visited-set (`_DOTPKG_VISITED`) — clean and low-overhead | No `dotpkg install` command; "install" is split across `init`, `add`, `sync` with subtle differences in root-bundle behavior — discoverable only by reading code |
| defaults.sh source-guard (`[[ "$source" == "local" ]]`) prevents remote code execution — explicit security boundary | `stow_check` calls `stow -n -v stow` and greps stderr for conflict strings; grep match is case-insensitive text scan, not structured output — fragile against stow version changes |
| Idempotent state recording: `state_add_bundle` only appends if name not present | `install_bundle` recursive dep calls inherit the caller's `$source`, so a local bundle's deps that came from GitHub will execute their `defaults.sh` (inherited "github" source = skipped); this is consistent behavior but not documented |
| Extensions install to all detected editors simultaneously — avoids per-editor configuration | `theme_target` silently skips if unset; no warning printed — themes can be authored but never installed without obvious diagnostic |

---

Claude Code | Model: Sonnet 4.6 | Aug-05-2026 05:24 UTC  
Wall-clock start: Wed Aug  5 05:22:55 UTC 2026 | Finish: Aug-05-2026 05:24 UTC
