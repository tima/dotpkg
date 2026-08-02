# dotpkg

A CLI tool and repo convention for managing macOS machine setup. Packages tools, configs, and system preferences into composable units that can bootstrap a blank Mac from a single curl command.

## Implementation Status

Phase 1 complete (2026-07-31):
- `bootstrap.sh` — curl target; installs Xcode CLT, Homebrew, stow, gum; clones dotpkg to ~/.dotpkg/; symlinks dotpkg to /usr/local/bin; runs `dotpkg init`
- `dotpkg` — main CLI; all commands implemented: init, add, sync, status, list, update, create, adopt
- `lib/state.sh` — state.json CRUD via python3 (ships with Xcode CLT)
- `lib/bundle.sh` — install_bundle, resolve_bundle, dependency traversal (visited-set), install_extensions
- `lib/stow.sh` — stow_check (conflict pre-check), stow_apply, stow_remove
- `lib/helpers.sh` — dotpkg_preset (keyboard/finder/dock/trackpad/screenshots/display/menubar/accent-color/spotlight/privacy), dotpkg_hotkey_disable, dotpkg_hotkey_set_corner, dotpkg_dock add, dotpkg_wallpaper, dotpkg_terminal_import
- `tests/test_bundle.sh` — 24 assertions covering state, visited-set, bundle_info_get, resolve_bundle, install_bundle

Phase 2 complete (2026-07-31):
- `dotpkg init` — prompt for repo path (or --repo flag), create config, install root bundle + optional profile
- `dotpkg add <bundle>` — resolve bundle (local/profile/sources/GitHub), install root first if needed, traverse deps (visited-set), fetch + pre-check + apply stow, brew bundle, defaults.sh, extensions, themes
- `dotpkg sync` — re-apply all installed bundles, idempotent
- `dotpkg status [--json]` — list installed bundles, JSON flag for AI
- `dotpkg list [--local|--remote]` — show available bundles, profiles, sources
- `dotpkg create <name>` — scaffold bundle with bundle.info
- CLI error handling: bundle not found, missing config, conflict detection
- INTEGRATION.md — manual test instructions; automated tests now in `tests/test_integration_phase2.sh` (34 assertions, no system side-effects)

Phase 3 complete (2026-08-01):
- `lib/bundle.sh` — `_source_cache_key` (normalizes user/repo, https://, git@ URLs to collision-free cache key), `_clone_source` (clones trusted source repos without preview), fixed `resolve_bundle` order: local → profiles → sources → GitHub shorthand
- Cache layout: `$DOTPKG_HOME/cache/sources/<key>/` for source repos, `$DOTPKG_HOME/cache/github/<user>/<repo>/` for GitHub shorthands
- `dotpkg list [--local|--remote]` — remote shows bundles within source caches + cached GitHub bundles (not raw sources file)
- `dotpkg update` — pulls each source repo and each cached GitHub bundle, then re-syncs
- `dotpkg create` uses `return 1` instead of `exit 1` (safe to source in tests)
- `tests/test_phase3.sh` — 20 assertions: cache key normalization, all 4 resolution tiers, local-wins-over-source precedence, create scaffold, install from source

Phase 4 complete (2026-08-01):
- `lib/state.sh` — `state_add_preset(name)` records applied presets in `installed_presets[]`; `state_add_bundle` accepts optional `stow_paths` (space-separated, stored as JSON array)
- `lib/helpers.sh` — `dotpkg_preset` propagates handler return codes; sources `$DOTPKG_HOME/presets/<category>.local.sh` after preset for per-machine overrides; calls `state_add_preset` on success; `_preset_finder` adds expand-save/print-dialogs and DSDontWriteNetworkStores/DSDontWriteUSBStores
- `lib/bundle.sh` — `install_bundle` collects top-level stow/ entries after `stow_apply`, passes to `state_add_bundle`
- `tests/test_helpers.sh` — 50 assertions: all preset categories (valid flags, invalid flags, default values), hotkey_disable, hotkey_set_corner, local override sourcing, installed_presets tracking, stow_paths in state; system commands mocked (defaults/killall/osascript/sqlite3) — no system side-effects

## Language

**Bundle**:
A directory containing assets to install on a machine. The atomic unit of composition in dotpkg. Contains any combination of a Brewfile, config files, editor extensions, theme files, macOS presets, and dependencies on other bundles. Only `bundle.info` is required.
_Avoid_: package, module, plugin

**Profile**:
A bundle whose sole purpose is listing other bundles. Contains only `requires.txt` — no packages, configs, or presets. Represents a machine identity or role (e.g., workstation, server, creative).
_Avoid_: meta-bundle, metapackage, role

**Preset**:
A named, built-in group of `defaults write` commands that ships with dotpkg. Bundles apply presets by name. Users cannot define new preset names — only dotpkg's curated set is valid. Individual values can be overridden locally.
_Avoid_: cluster, defaults group, preference set

**Source**:
A git repository registered in `~/.dotpkg/sources` as a provider of bundles. Sources are opted-in by the user and treated as trusted. Distinct from GitHub shorthand.
_Avoid_: remote, registry, feed

**GitHub shorthand**:
A `user/repo` reference that resolves to a single GitHub repository whose root directory is a bundle. The repo itself is the bundle — `bundle.info` lives at the root. One repo, one bundle.
_Avoid_: shorthand bundle, remote bundle (ambiguous)

**Installed**:
A bundle that has been applied to the current machine — its Brewfile run, configs stowed, presets applied, extensions installed. Tracked in `~/.dotpkg/state.json`. The only bundle state; there is no "active vs inactive" distinction.
_Avoid_: active, enabled, applied

**Adopt**:
The process of importing existing machine state into dotpkg management. Two forms: generating a Brewfile from currently-installed Homebrew packages, or moving an existing config file into a bundle's stow package.
_Avoid_: import, migrate, onboard

**Sync**:
Re-applying all installed bundles to the current machine. Idempotent. Used to reconcile machine state after bundle changes or a fresh clone.
_Avoid_: apply, install-all, restore

**Bootstrap**:
The process of going from a stock Mac to a dotpkg-managed machine. Initiated by a curl one-liner. Installs Xcode CLT, Homebrew, stow, gum, then clones dotpkg and hands off to `dotpkg init`.
_Avoid_: setup, onboarding, provisioning

## Development Practice

**Branching**: commit directly to main. Branch-per-feature adds ceremony with no benefit for a solo project. Add branches when external contributors join.

**Commit boundaries**: commit at the end of each logical unit of work — a completed phase, a self-contained feature, a docs update. Never let untracked or unstaged work accumulate across multiple sessions. Natural boundaries: phase completion, new lib file, new test suite, docs, LICENSE/README.

**Running tests before commit**:
```bash
bash tests/test_bundle.sh
bash tests/test_phase3.sh
bash tests/test_integration_phase2.sh
bash tests/test_helpers.sh
```

All suites must pass (currently 150 assertions across 4 files). No framework — plain bash with assert helpers and mocked system commands.

## Change Log

**2026-08-02**: Added dock helpers (clear, set) per refactor analysis gap #1. All tests pass (150 assertions).
