# dotpkg — Code Intelligence Report

**Objective:** How does bundle source resolution work — how does dotpkg determine whether a bundle is local or from GitHub, clone remote bundles, and what path does a spec like `user/repo` follow to become an installed bundle directory?
**Repository:** /Users/tappnel/projects/dotpkg

---

## Executive Summary

Bundle source is determined by a single glob check: `[[ "$bundle_name" == */* ]]` in `cmd_add` (`dotpkg:97`). Resolution runs through 5 ordered steps in `resolve_bundle` (`lib/bundle.sh:44-91`). A `user/repo` spec skips steps 0-3, enters step 4, clones to a temp dir via `git clone --depth=1`, prompts for confirmation, then copies to `~/.dotpkg/cache/github/user/repo` — that directory is what `install_bundle` receives.

---

## Code Architecture

Entry point: `dotpkg` (436 lines), sources all `$DOTPKG_HOME/lib/*.sh` on startup (line 14).

Lib files (verified via `ls /Users/tappnel/projects/dotpkg/lib/`):
- `lib/bundle.sh` (255 lines) — resolution, cloning, install orchestration
- `lib/helpers.sh` (294 lines) — preset and macOS helper functions
- `lib/state.sh` (72 lines) — state.json read/write via inline Python
- `lib/prompt.sh` (34 lines) — gum wrappers
- `lib/stow.sh` (18 lines) — stow conflict check and apply

Key functions by file:
- `dotpkg`: `cmd_add`, `cmd_sync`, `cmd_init`, `cmd_update`, `cmd_list` (commands)
- `lib/bundle.sh`: `resolve_bundle`, `_fetch_github_bundle`, `_clone_source`, `install_bundle`
- `lib/state.sh`: `state_add_bundle`, `state_list_bundles`, `state_bundle_installed`

---

## Answer to Your Question

### How dotpkg detects local vs GitHub

In `cmd_add` (`dotpkg:94-99`), after `resolve_bundle` returns the directory:

```bash
[[ "$bundle_name" == */* ]] && bundle_source="github" || bundle_source="local"
```

Presence of `/` in the spec sets `bundle_source="github"`; absence sets `"local"`. This label is passed to `install_bundle` and stored in `state.json`. It governs one branch in step 4 of `install_bundle`: `defaults.sh` is skipped when `source != "local"` (`lib/bundle.sh:225-231`).

Exclusivity verification: searched for all `github` and `shorthand` references across `dotpkg` and `lib/` (14 matches). The `*/*` pattern is the only mechanism that sets `bundle_source="github"` at install time. Sources (step 3 of resolution) are always labelled `"local"` by `cmd_add` because source bundle specs never contain `/`.

### The 5-step resolution sequence in `resolve_bundle` (lib/bundle.sh:44-91)

All 5 steps run in order; the function returns on the first match.

**Step 0 — Root bundle** (`lib/bundle.sh:48-51`)
Reads `$DOTFILES_DIR/bundle.info`, extracts `name=`. If `name` matches the spec, returns `$DOTFILES_DIR`.

**Step 1 — Local bundle** (`lib/bundle.sh:55-56`)
Checks `$DOTFILES_DIR/bundles/$name/`. Requires both directory and `bundle.info` present.

**Step 2 — Profile** (`lib/bundle.sh:59-60`)
Checks `$DOTFILES_DIR/profiles/$name/`. Same existence check.

**Step 3 — Source repos** (`lib/bundle.sh:63-77`)
Reads `~/.dotpkg/sources` line by line. For each repo:
1. Derives a cache key via `_source_cache_key` (strips `.git`, URL scheme, `git@` prefix, replaces `:` with `/`)
2. If `$DOTPKG_HOME/cache/sources/$source_key` doesn't exist, calls `_clone_source "$repo" "$source_cache" || continue`
3. Checks whether `$source_cache/bundles/$name/bundle.info` exists; if so, returns that path

`_clone_source` (`lib/bundle.sh:29-41`) accepts either `user/repo` shorthand or full URL. Shorthand triggers the regex `^[^/@:\ ]+/[^/@:\ ]+$` and constructs `https://github.com/${repo}.git`. It clones directly to the cache directory (no temp+copy, no user confirmation).

**Step 4 — GitHub shorthand** (`lib/bundle.sh:79-87`)
Triggers only when `[[ "$name" == */* ]]`. Sets `cache_dir="$DOTPKG_HOME/cache/github/$name"`. If that directory doesn't exist, calls `_fetch_github_bundle "$name" "$cache_dir"`. Returns `$cache_dir`.

`_fetch_github_bundle` has 1 call site (verified: `lib/bundle.sh:83`).

**Fallthrough — not found** (`lib/bundle.sh:89-91`)
Prints `"dotpkg: bundle not found: $name"` to stderr, returns 1.

### Full path for a `user/repo` spec

1. `dotpkg add user/repo` dispatches to `cmd_add "user/repo"` (`dotpkg:420-422`)
2. `cmd_add` optionally installs the root bundle first (if present and not yet installed, `dotpkg:84-91`)
3. `bundle_dir=$(resolve_bundle "user/repo")` (`dotpkg:94`)
4. Inside `resolve_bundle`:
   - Step 0: `name` from root `bundle.info` is not `"user/repo"` — skip
   - Step 1: `$DOTFILES_DIR/bundles/user/repo/` — no such directory — skip
   - Step 2: `$DOTFILES_DIR/profiles/user/repo/` — no such directory — skip
   - Step 3: sources file absent or no bundle named `"user/repo"` within any source — skip
   - Step 4: `"user/repo"` matches `*/*`; `cache_dir="$DOTPKG_HOME/cache/github/user/repo"`
5. If `$cache_dir` doesn't exist, `_fetch_github_bundle "user/repo" "$cache_dir"` runs:
   a. `tmp_dir=$(mktemp -d)`, trap set: `rm -rf '$tmp_dir'` on RETURN
   b. `git clone --depth=1 --quiet "https://github.com/user/repo.git" "$tmp_dir"` — aborts with error on failure
   c. Checks `$tmp_dir/bundle.info` exists — aborts if missing
   d. Previews 5 files from `$tmp_dir`: `bundle.info`, `Brewfile`, `defaults.sh`, `extensions.txt`, `requires.txt` (skips absent files)
   e. `_gum_confirm "Install bundle user/repo?"` — aborts if declined
   f. `mkdir -p "$(dirname "$cache_dir")"` creates `~/.dotpkg/cache/github/user/`
   g. `cp -r "$tmp_dir" "$cache_dir"` — persists bundle to `~/.dotpkg/cache/github/user/repo`
   h. Trap fires on RETURN, deletes `$tmp_dir`
6. `resolve_bundle` returns `"$DOTPKG_HOME/cache/github/user/repo"`
7. Back in `cmd_add`: `bundle_source="github"` (because `"user/repo"` matches `*/*`)
8. `install_bundle "$DOTPKG_HOME/cache/github/user/repo" "github"` runs 6 steps (see below)

### install_bundle steps (lib/bundle.sh:168-255)

All 6 steps run unconditionally unless guarded:

1. **Dependencies** (`lib/bundle.sh:193-203`): reads `requires.txt` line by line; calls `resolve_bundle "$dep"` and recurses with `install_bundle "$dep_dir" "$source"`. Visited-set prevents cycles.
2. **Brewfile** (`lib/bundle.sh:206-209`): runs `brew bundle --file=.../Brewfile --no-upgrade`. Guard: file must exist.
3. **Stow** (`lib/bundle.sh:212-222`): reads `stow_target` from `bundle.info` (defaults to `$HOME`); calls `stow_check` then `stow_apply`. Guard: `stow/` directory must exist.
4. **defaults.sh** (`lib/bundle.sh:225-232`): sourced into current process with `. "$bundle_dir/defaults.sh"`. Guard: file must exist AND `source == "local"`. For `source="github"`, this step is skipped with a message printed to stderr.
5. **Editor extensions** (`lib/bundle.sh:236-239`): calls `install_extensions "$bundle_dir/extensions.txt"`. Guard: file must exist.
6. **Themes** (`lib/bundle.sh:242-251`): copies `themes/` contents to `theme_target` from `bundle.info`. Guard: `themes/` dir must exist AND `theme_target` must be non-empty in `bundle.info`.

After all 6 steps: `state_add_bundle "$name" "$source" "$stow_paths"` (`lib/bundle.sh:253`) records bundle `name` (from `bundle.info`), `source` label, and stow paths into `state.json`.

### Difference between GitHub shorthand and source repo cloning

| Aspect | GitHub shorthand (`user/repo`) | Source repo (`~/.dotpkg/sources`) |
|--------|-------------------------------|-----------------------------------|
| Function | `_fetch_github_bundle` | `_clone_source` |
| Temp dir | Yes (`mktemp -d`, cleaned on RETURN) | No (clones directly to cache) |
| User confirmation | Required (`_gum_confirm`) | Not required |
| Clone depth | `--depth=1` | No `--depth` flag (full clone) |
| Cache path | `~/.dotpkg/cache/github/user/repo` | `~/.dotpkg/cache/sources/<key>` |
| bundle.info location | Repo root | `bundles/<name>/bundle.info` inside cloned repo |
| source label in state | `"github"` | `"local"` (set by `cmd_add` based on no `/` in spec name) |

---

## Extension/Integration Points

**Adding a new resolution step:** `resolve_bundle` in `lib/bundle.sh:44-91` is a linear if/return chain. A new source type inserts a new block before the fallthrough at line 89. The function contract is: echo the resolved directory path to stdout and return 0 on success; print error to stderr and return 1 on failure.

**Adding a new bundle asset type:** `install_bundle` in `lib/bundle.sh:168-255` runs 6 sequential steps. A new step (e.g., Ansible inventory) adds a guarded block before line 253. It should respect the `source` label if code execution is involved.

**Source registration:** `~/.dotpkg/sources` is a plain text file, one repo per line, `#` for comments. Adding a line makes that repo searchable in step 3 of resolution. The repo must have a `bundles/` subdirectory with named bundle directories.

Files to touch (verified by tracing; exhaustive search not performed — verify no additional call sites exist before implementing):
- `lib/bundle.sh` — `resolve_bundle` and `install_bundle`
- `dotpkg` — `cmd_add` for `bundle_source` label logic

---

## Code Reading Guide

1. Read `dotpkg:76-100` (`cmd_add`) — the top-level flow from CLI spec to `install_bundle`
2. Read `lib/bundle.sh:44-91` (`resolve_bundle`) — all 5 resolution steps
3. Read `lib/bundle.sh:94-133` (`_fetch_github_bundle`) — GitHub clone + confirm flow
4. Read `lib/bundle.sh:29-41` (`_clone_source`) — source repo clone (no confirmation)
5. Read `lib/bundle.sh:168-255` (`install_bundle`) — all 6 install steps and guards
6. Read `lib/state.sh:22-36` (`state_add_bundle`) — how the installed record is persisted

---

## Strengths & Weaknesses

| Strengths | Weaknesses |
|-----------|-----------|
| Security gate: GitHub bundles require explicit preview + confirmation before any file is persisted; source repos (pre-trusted) skip this (`lib/bundle.sh:93`) | `cmd_sync` hardcodes `"local"` as source for all bundles (`dotpkg:116`), including originally-GitHub ones; would also apply `defaults.sh` from GitHub bundles on re-sync if the cache dir were re-found |
| Visited-set prevents infinite dependency cycles with no external dependency (`lib/bundle.sh:7-13, 184-188`) | GitHub bundle names stored in state.json come from `bundle.info`'s `name` field (not `user/repo`); `cmd_sync` calls `resolve_bundle` with that plain name, which never matches `*/*`, so `resolve_bundle` cannot find the cached GitHub directory — GitHub bundles silently skip during sync |
| `_fetch_github_bundle` uses a RETURN trap to guarantee temp dir cleanup even on failure or interruption (`lib/bundle.sh:102`) | `_clone_source` clones full history (no `--depth=1`) for source repos, while GitHub shorthand clones shallow — inconsistent behavior for similar remote operations |
| Resolution order is documented both in code comments and in `cmd_help` output, keeping spec and implementation aligned | No validation that `user/repo` in `requires.txt` actually resolves before install starts; dependency errors surface mid-install, not as pre-flight checks |

---

Claude Code | Sonnet 4.6 | Start: Wed Aug 5 05:43:31 UTC 2026 | Finish: Wed Aug 5 05:45:33 UTC 2026
