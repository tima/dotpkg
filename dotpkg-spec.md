# dotpkg -- Future State Specification

Version: 0.1 (draft)
Status: Draft -- not yet validated against implementation


## What dotpkg Is

dotpkg is a CLI tool and repo convention for managing macOS machine setup and maintenance. It packages Homebrew formulas, casks, fonts, config files, editor extensions, themes, and macOS system presets into composable, shareable units called bundles.

Goals:

- Go from a blank Mac to a fully configured system with a single curl command
- Make it easy to pull in bundles of tools for a specific context (development, video editing, AI work, etc.)
- Provide a deterministic layer that AI agents can query, debug, and build on
- Reduce friction for both initial setup and ongoing maintenance
- Zero dependencies beyond what ships with macOS (bash, curl) -- everything else is bootstrapped


## Three Scenarios

dotpkg handles three distinct starting points:

1. **New machine.** Nothing installed. The curl one-liner bootstraps everything from scratch.
2. **Existing machine, unmanaged.** Tools are installed, configs exist, but nothing is tracked. dotpkg imports the current state into bundles.
3. **Existing machine, different dotfiles system.** User is migrating from chezmoi, yadm, bare-git, etc. Documented as a manual process in v1 -- no automated conversion.


## Architecture

### Dependency Chain

A stock Mac provides bash, curl, and (after Xcode CLT) git. dotpkg bootstraps everything else in a strict order:

```
curl one-liner (hosted as a GitHub Gist or raw file)
  |
  v
bootstrap.sh (downloaded and executed)
  1. Trigger Xcode Command Line Tools install (provides git)
  2. Install Homebrew
  3. brew install stow gum
  4. Clone the dotpkg repo to ~/.dotpkg/
  5. Symlink dotpkg script to /usr/local/bin/dotpkg
  6. dotpkg init takes over
```

### Platform Support

- Apple Silicon: primary target, fully supported
- Apple Intel: deferred, may be added later

### Implementation

Pure bash. Every interactive prompt uses gum. Every command supports non-interactive use via flags for scripting and AI consumption.


## Bundles

A bundle is a directory containing assets to install. The repository root is itself a bundle (personal settings and shared utils). Additional bundles live in `~/dotfiles/bundles/` organized by purpose (dev-tools, video-editor, etc.). Only `bundle.info` is required -- all other files are optional. If a file isn't present, that asset type is skipped.

### Bundle Directory Structure

```
<bundle-name>/
  bundle.info        # required -- metadata and config
  Brewfile            # Homebrew formulas, casks, fonts
  stow/              # config files to symlink (mirrors target dir structure)
  defaults.sh        # macOS presets and helper function calls to apply
  extensions.txt     # editor extension IDs (one per line)
  themes/            # theme files to copy into app-specific locations
  requires.txt       # bundle dependencies (one bundle name per line)
  README.md          # documentation
```

### Bundle Organization

The dotfiles repo structure is:

```
~/dotfiles/
  bundle.info        # root bundle (personal settings, foundational utils)
  Brewfile           # personal utilities (tree, jq, ripgrep, etc.)
  defaults.sh        # personal macOS settings (keyboard, finder, hotkeys, wallpaper)
  extensions.txt     # personal editor extensions
  stow/              # personal configs (git, shell, etc.)
  bundles/           # purpose-driven bundles
    dev-tools/
    video-editor/
    ansible-dev/
    (etc.)
  profiles/          # machine identities
    workstation/
    minimal/
    (etc.)
```

Profiles list bundles to install. The root bundle (personal) is installed like any other — always included when it's in a profile's `requires.txt`.

### bundle.info

Plain text key-value pairs. No parser needed.

```
name=ansible-dev
description=Ansible development tools and configuration
author=tima
type=bundle
```

Valid values for `type`: `bundle` (default), `profile`.

Optional fields:

```
stow_target=~/Library/Application Support/Code/User
```

If `stow_target` is not specified, stow targets `$HOME`. If a bundle needs multiple stow targets, split it into separate bundles.

### Brewfile

Standard Homebrew bundle format. No dotpkg-specific extensions.

```
brew "ansible"
brew "ansible-lint"
brew "python@3.12"
cask "visual-studio-code"
```

### stow/

A directory tree mirroring the target directory structure. Managed by GNU Stow.

Example for a bundle targeting $HOME:
```
stow/
  .zshrc
  .config/
    starship.toml
```

### defaults.sh

A shell script that applies macOS presets and system configuration. dotpkg sources this file (`. defaults.sh`) into its own process, making preset and helper functions available. Sourced with fail-fast behavior: any non-zero exit aborts the bundle install.

**Personal-only helpers** (root bundle only):
- `dotpkg_preset` — keyboard, finder, trackpad, display, accent-color, screenshot-location, menubar (personal settings apply to all machines)
- `dotpkg_hotkey_*` — disable/set hotkeys (personal choice, not tied to bundles)
- `dotpkg_wallpaper` — set desktop wallpaper (personal identity, consistent across machines)
- `dotpkg_terminal_import` — set terminal theme (personal, not tool-specific)

**Bundle helpers** (any bundle):
- `dotpkg_dock add <app> [<app> ...]` — add apps to dock (tool bundles add their apps)
- `dotpkg_preset` for non-personal categories (TBD: which are bundle-scoped)

**Convention vs. enforcement:**
Presets and helpers are the recommended path, but `defaults.sh` can contain arbitrary bash, raw `defaults write` calls, or anything else. dotpkg does not validate or restrict. Use helpers for safety and idempotency; raw commands are your responsibility.

Example (personal bundle):
```
#!/bin/bash
dotpkg_preset keyboard --key-repeat 2 --initial-key-repeat 15
dotpkg_preset finder
dotpkg_hotkey_disable spotlight
dotpkg_wallpaper ~/dotfiles/wallpapers/nord_polarnight_4.png
dotpkg_terminal_import ~/dotfiles/themes/catppuccin-mocha.terminal
```

Example (tool bundle):
```
#!/bin/bash
dotpkg_dock add "Visual Studio Code" Handbrake
```

### extensions.txt

Editor extension IDs, one per line. dotpkg detects which compatible editors are installed (VS Code, Cursor, Codium) and runs the appropriate install command for each. Extension IDs are shared across these editors where available.

**Error handling:** Extension install failures are categorized:
- **Unavailable** (not in marketplace) — emit a named warning, skip, continue install
- **Other failures** (network, auth, command error) — abort bundle install, user must fix and retry

This distinguishes between expected missing extensions and unexpected infrastructure problems.

```
arcticicestudio.nord-visual-studio-code
ms-python.python
redhat.vscode-yaml
```

### themes/

Files copied (not symlinked) into app-specific locations. For sandboxed apps or Group Containers where symlinks don't work. Copy targets are declared in bundle.info:

```
theme_target=~/Library/Group Containers/xxx.app/themes
```

### requires.txt

Bundle dependencies, one per line. dotpkg installs all required bundles before the current one. Dependency resolution uses visited-set traversal: handles circular dependencies (logs a warning, skips the duplicate) and deduplicates diamonds (A requires B and C, B also requires C — C installs once).

```
dev-base
shell-tools
```

Bundles are resolved in this order: local directory, user remotes, GitHub shorthand. Remote bundles are fetched before conflict detection runs.


## Profiles

A profile is a bundle whose `type=profile` in bundle.info. It contains only a `requires.txt` listing other bundles (including the root personal bundle) -- no packages, configs, or presets of its own. Profiles represent a machine identity or role.

When you install a profile, dotpkg:
1. Always installs the root bundle (personal settings) first if not already installed
2. Installs all bundles listed in the profile's requires.txt

Example `workstation/bundle.info`:
```
name=workstation
description=Full workstation setup for development and creative work
author=tima
type=profile
```

Example `workstation/requires.txt`:
```
personal
dev-tools
claude-code
video-editor
```

The curl one-liner can accept a profile name to go from blank to fully configured:
```
curl -fsSL https://raw.githubusercontent.com/.../bootstrap.sh | bash -s workstation
```

The personal bundle is optional in requires.txt if you're installing it manually, but recommended for clarity.


## Bundle Sources

Bundles can come from three tiers, resolved in order:

1. **Local** -- `~/dotfiles/bundles/` directory. Always checked first.
2. **User remotes** -- git repos listed in `~/.dotpkg/sources`. Your own or team repos.
3. **GitHub shorthand** -- `user/repo` fetched directly from GitHub. The repo root is the bundle -- `bundle.info` must be at the root. One repo, one bundle. Cloned into `~/.dotpkg/cache/` on first use. 

   **Trust model:** GitHub shorthand bundles show a full preview (bundle.info, Brewfile, defaults.sh, extensions.txt, requires.txt) and require explicit `y` confirmation before any action. User-remote bundles (from `~/.dotpkg/sources`) are treated as trusted (you added them deliberately) and skip preview.

### sources file

Plain text, one repo per line:

```
tima/dotpkg-bundles
myorg/shared-bundles
git@github.internal:team/bundles.git
```


## Presets and Helpers

**Presets** are built-in, curated groups of `defaults write` commands that ship with dotpkg. `defaults.sh` calls `dotpkg_preset <name> [--flag value ...]` to apply a group with optional customization.

**Helpers** are functions that handle complex operations — dock manipulation, wallpaper setting, hotkey configuration, terminal import — without exposing the underlying plist/defaults complexity.

### Built-in Presets (TBD: values and parameter signatures)

Preset categories with example parameter usage (signatures TBD):

- keyboard -- `dotpkg_preset keyboard --key-repeat N --initial-key-repeat N`
- trackpad -- `dotpkg_preset trackpad [--enable-tap-to-click true|false]`
- dock -- `dotpkg_preset dock --icon-size N`
- finder -- `dotpkg_preset finder`
- screenshots -- `dotpkg_preset screenshots --location PATH`
- display -- `dotpkg_preset display --screensaver-idle SECONDS`
- menubar -- `dotpkg_preset menubar [--show-battery-percentage true|false]`
- accent-color -- `dotpkg_preset accent-color --value COLOR`
- spotlight -- `dotpkg_preset spotlight [--disable-web-search true|false]`
- privacy -- `dotpkg_preset privacy [--disable-analytics true|false]`

### Built-in Helpers (TBD: implementation details)

- `dotpkg_hotkey_disable <name>` -- disable system hotkeys (e.g., `spotlight`, `mission-control`)
- `dotpkg_hotkey_set_corner <position> <action>` -- configure hot corners (TBD: position and action enums)
- `dotpkg_dock add <app-name> [<app-name> ...]` -- append apps to the dock
- `dotpkg_dock clear` -- remove all apps from the dock
- `dotpkg_dock set <app-name> [<app-name> ...]` -- replace dock contents (clear + add)
- `dotpkg_wallpaper <path>` -- set desktop wallpaper across all spaces/displays
- `dotpkg_terminal_import <path-to-terminal-file>` -- import and set as default terminal theme

Users can override individual values within a preset using the `.local` pattern.


## Machine-Local Overrides

dotpkg bakes in the `.local` convention for per-machine customization. Any config file managed by dotpkg that supports sourcing (shell configs, defaults scripts) will automatically source a `.local` variant if one exists.

- `~/.zshrc` sources `~/.zshrc.local`
- `~/.gitconfig` includes `~/.gitconfig.local`
- Presets check for `~/.dotpkg/presets/<name>.local.sh` before applying

`.local` files are never tracked in git. They allow per-machine environment variables, paths, credentials, and preference overrides without diverging from shared config.


## State Tracking

dotpkg tracks what's installed on each machine in a local-only manifest. This file is NOT tracked in git -- different machines have different bundles.

Location: `~/.dotpkg/state.json`

```json
{
  "installed_bundles": [
    {
      "name": "dev-base",
      "source": "local",
      "installed_at": "2026-07-25",
      "stow_paths": [".zshrc", ".config/starship.toml"]
    },
    {
      "name": "tima/claude-code",
      "source": "github",
      "installed_at": "2026-07-25",
      "stow_paths": [".config/claude/settings.json"]
    }
  ],
  "installed_presets": ["keyboard", "dock", "finder"]
}
```

The repo defines what's available. The local state tracks what's installed here.


## CLI Commands

### dotpkg init

Bootstrap a new or existing machine. Run automatically by the curl one-liner or manually.

- Prompts for dotfiles repo location (default: `~/dotfiles`)
- Creates `~/dotfiles/bundles/` if it doesn't exist
- Installs the root bundle (personal settings) unconditionally
- Optionally accepts a profile name to install immediately (root bundle + profile bundles)

```
dotpkg init
dotpkg init --profile workstation
dotpkg init --repo ~/my-dotfiles --profile workstation
```

### dotpkg add <bundle>

Install a bundle. Always installs root bundle (personal settings) first if not already installed. Resolves dependencies via visited-set traversal (handles cycles with warnings, deduplicates diamonds), fetches remote bundles, runs Brewfile (without `--upgrade`), stows configs, applies presets, installs extensions. Reads `bundle.info` type -- profiles are handled the same as bundles.

Conflict detection: fetches all remote bundles, then runs `stow --simulate` to pre-check for path conflicts before any changes. Aborts with a named conflict message if detected.

For GitHub shorthand bundles: shows a gum-formatted preview of all bundle files (bundle.info, Brewfile, defaults.sh, extensions.txt, requires.txt) and requires explicit `y` confirmation before proceeding. User-remote bundles (from ~/.dotpkg/sources) are treated as trusted and skip preview.

Extension install failures are categorized: unavailable extensions (not in editor's marketplace) emit a named warning and continue; other errors (network, auth) abort the install.

```
dotpkg add dev-base
dotpkg add tima/claude-code
dotpkg add workstation
```

### dotpkg sync

Re-apply all installed bundles and reconcile to the current profile. Idempotent. Root bundle (personal settings) is always re-applied. For bundles listed in the active profile's requires.txt: re-run Brewfile (without `--upgrade`), re-stow configs (including conflict detection), re-apply presets, re-install extensions.

Reconciliation: if a bundle is in `~/.dotpkg/state.json` but no longer listed in any active profile, remove its stow links and delete from state.json.

Theme files are always re-copied unconditionally (no cleanup of old paths). If theme_target contains per-machine paths, use `.local` override in bundle.info.

```
dotpkg sync
```

### dotpkg status

Show installed bundles, active presets, and sync state. Default output is human-readable. `--json` flag for AI consumers.

```
dotpkg status
dotpkg status --json
```

### dotpkg list

List available bundles from all sources.

```
dotpkg list
dotpkg list --remote
dotpkg list --local
```

### dotpkg update

Pull latest versions of remote bundles and re-sync (calls `dotpkg sync` internally). Uses `brew bundle` without `--upgrade` -- adds new formulas, does not upgrade existing ones. Version management is separate: users control formula upgrades via `brew upgrade`.

```
dotpkg update
```

### dotpkg create <name>

Scaffold a new bundle directory with bundle.info and placeholder files.

```
dotpkg create my-new-bundle
```

### dotpkg adopt

Import existing state into bundles. Two modes:

- `dotpkg adopt --brew` -- run `brew bundle dump`, show the full Brewfile via gum for review, prompt for which bundle to assign it to, require explicit confirmation before writing. Single confirmation for the whole Brewfile.
- `dotpkg adopt <file>` -- move a config file into a bundle's stow package interactively, one file at a time.

```
dotpkg adopt --brew
dotpkg adopt ~/.zshrc --bundle shell-config
```

dotpkg does not bulk-import without confirmation.


## AI Interface

dotpkg is designed to be a reliable foundation for AI agents. Key properties:

- `dotpkg status --json` provides machine-readable state
- Every command supports non-interactive mode via flags (no gum prompts when piped or flagged)
- Consistent, predictable output suitable for parsing
- `dotpkg --help` and subcommand help are descriptive enough for an agent to discover capabilities

AI agents can use dotpkg to:

- Query what tools are available on the machine
- Check if a required tool is installed before suggesting it
- Debug configuration issues by inspecting bundle state
- Recommend bundles based on adopted/installed state
- Potentially assist with advanced operations like uninstall (deferred from v1 CLI)


## Scope

### v1

- CLI: init, add, sync, status, list, update, create, adopt
- Bundle format: bundle.info, Brewfile, stow/, defaults.sh, extensions.txt, themes/, requires.txt
- Root bundle (personal settings) always auto-installs unconditionally
- Profiles (requirement lists with root bundle + tool bundles)
- Bundle sources: local, user remotes, GitHub shorthand
- Presets: built-in curated set (TBD: signatures and values per category), personal-only and convention-only
- Helpers: personal-only (wallpaper, terminal, hotkeys, keyboard/finder/trackpad/menubar/accent-color/screenshot presets); bundle-scoped (dock add/clear/set)
- Local state tracking (~/.dotpkg/state.json) with stow path tracking per bundle
- Machine-local overrides (.local pattern)
- Dependency resolution: visited-set traversal (logs warnings on cycles, deduplicates diamonds)
- Stow conflict pre-check: fetch remotes, then `stow --simulate`, abort with named conflict if detected
- GitHub shorthand trust model: full bundle preview + explicit y confirmation; user remotes (sources) are trusted and skip preview
- Extension failure categorization: unavailable (warn+continue), other errors (abort)
- Theme re-copy: unconditional on every sync, no cleanup (use `.local` for per-machine paths)
- Brewfile semantics: `brew bundle` without `--upgrade` for both add and update; version management is separate
- defaults.sh sourced with fail-fast (non-zero exit aborts bundle install); convention-only preset/helper usage, arbitrary bash allowed
- gum-based interactive prompts
- Non-interactive mode via flags for all commands
- --json flag on status
- Apple Silicon support

### Deferred

- Bundle removal/uninstall (reference counting problem)
- Apple Intel support
- Automated migration from other dotfiles systems
- Community bundle registry/index
- Bundle versioning and pinning
- Custom presets defined in bundles
- Per-formula adoption (interactive per-formula mode for adopt --brew)
- Hot corner fine-grained assignment beyond disable
- Preset signatures (TBD)
- Helper implementation details (TBD)


## Open Questions / TBD

- [ ] **Preset signatures and values (TBD)**: finalize `--flag value` syntax and defaults for each preset category
- [ ] **Helper implementation details (TBD)**: wallpaper plist/sqlite handling, dock manipulation without nuking contents, hotkey ID mappings
- [ ] **Quick wins to include (TBD)**: hot corners, expand save/print dialogs, disable .DS_Store on network volumes, Spotlight indexing priorities
- [ ] **stow_target for themes**: how to handle apps with Group Container paths that vary per machine
- [ ] **gum as a hard dependency vs graceful fallback**: if not installed
- [ ] **CLI name**: `dotpkg` is functional but open to a name with more personality
