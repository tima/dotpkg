# dotpkg

macOS machine setup and dotfiles manager. Packages Homebrew formulas, config files, editor extensions, themes, and system preferences into composable units called **bundles**. Go from a blank Mac to a fully configured system with a single curl command.

Zero runtime dependencies beyond what ships with macOS — everything else is bootstrapped.

---

## Table of Contents

- [Concepts](#concepts)
- [Bootstrap: new machine](#bootstrap-new-machine)
- [Existing machine](#existing-machine)
- [Your dotfiles repo](#your-dotfiles-repo)
- [Bundle authoring](#bundle-authoring)
  - [bundle.info](#bundleinfo)
  - [Brewfile](#brewfile)
  - [stow/ — config files](#stow--config-files)
  - [defaults.sh — presets and helpers](#defaultssh--presets-and-helpers)
  - [extensions.txt](#extensionstxt)
  - [themes/](#themes)
  - [requires.txt — dependencies](#requirestxt--dependencies)
- [Profiles](#profiles)
- [Bundle sources](#bundle-sources)
- [CLI reference](#cli-reference)
- [AI interface](#ai-interface)

---

## Concepts

**Bundle** — a directory with assets to install on a machine. Contains any combination of a Brewfile, config files, editor extensions, theme files, macOS preferences, and dependencies on other bundles. Only `bundle.info` is required.

**Profile** — a bundle whose only job is listing other bundles in `requires.txt`. Represents a machine identity or role (workstation, minimal, creative).

**Root bundle** — the dotfiles repo root itself is a bundle. It holds your personal settings: shell config, git config, keyboard preferences, wallpaper, etc. Always installed first.

**Preset** — a named, built-in group of `defaults write` commands. Applied by calling `dotpkg_preset <category>` in a bundle's `defaults.sh`.

**State** — dotpkg tracks what's installed per machine in `~/.dotpkg/state.json`. This file is not tracked in git — different machines have different bundles installed.

---

## Bootstrap: new machine

On a blank Mac, run:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/dotpkg/main/bootstrap.sh | bash
```

With a profile:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/dotpkg/main/bootstrap.sh | bash -s workstation
```

This:
1. Installs Xcode Command Line Tools (provides git)
2. Installs Homebrew
3. Installs `stow` and `gum` via brew
4. Clones dotpkg to `~/.dotpkg/`
5. Symlinks `dotpkg` to `/usr/local/bin/`
6. Runs `dotpkg init` to install your dotfiles

After bootstrap, `dotpkg` is on your PATH permanently.

---

## Existing machine

If dotpkg is already installed, initialize against your dotfiles repo:

```bash
dotpkg init --repo ~/dotfiles
dotpkg init --repo ~/dotfiles --profile workstation
```

Import existing state into bundles:

```bash
dotpkg adopt --brew                                  # import Homebrew packages
dotpkg adopt ~/.zshrc --bundle shell-config          # move a config file into a bundle
```

---

## Your dotfiles repo

Recommended structure:

```
~/dotfiles/
  bundle.info          # root bundle metadata
  Brewfile             # personal CLI tools
  defaults.sh          # personal macOS settings
  extensions.txt       # personal editor extensions
  stow/                # personal configs (.zshrc, .gitconfig, etc.)
  bundles/             # purpose-driven bundles
    dev-tools/
    video-editor/
    ansible-dev/
  profiles/            # machine identities
    workstation/
    minimal/
```

The repo root is itself a bundle — personal settings that apply on every machine. Bundles in `bundles/` are optional, installed explicitly with `dotpkg add` or via a profile.

---

## Bundle authoring

Create a new bundle scaffold:

```bash
dotpkg create my-bundle
```

This creates `bundles/my-bundle/` with a starter `bundle.info` and `stow/` dir. Add files as needed — all are optional except `bundle.info`.

### bundle.info

Plain key-value pairs. No parser needed.

```
name=dev-tools
description=Development tools and configuration
author=yourname
type=bundle
```

`type` is `bundle` (default) or `profile`. The `name` field must match the directory name for local bundles.

Optional:

```
stow_target=~/Library/Application Support/Code/User
```

If `stow_target` is omitted, stow targets `$HOME`. If a bundle needs multiple stow targets, split it into separate bundles.

For theme file destinations:

```
theme_target=~/Library/Application Support/SomeApp/themes
```

### Brewfile

Standard Homebrew Bundle format. dotpkg runs `brew bundle` without `--upgrade` — adds missing formulas, never upgrades existing ones. Version management is separate.

```
brew "ripgrep"
brew "fd"
brew "python@3.12"
cask "visual-studio-code"
cask "docker"
tap "homebrew/cask-fonts"
cask "font-jetbrains-mono-nerd-font"
```

### stow/ — config files

A directory tree that mirrors the target directory (default: `$HOME`). GNU Stow creates symlinks from the target into your bundle. dotpkg runs a conflict pre-check before symlinking — if a file already exists and is not managed by stow, the install aborts with a named error.

Example for a shell config bundle:

```
stow/
  .zshrc
  .gitconfig
  .config/
    starship.toml
    nvim/
      init.lua
```

After `dotpkg add shell-config`, these appear as symlinks in `$HOME`.

If `stow_target` points elsewhere:

```
stow/
  settings.json      # -> ~/Library/Application Support/Code/User/settings.json
  keybindings.json
```

### defaults.sh — presets and helpers

A shell script sourced (not executed as a subprocess) into dotpkg's process. Preset and helper functions are available without any import. Sourced with fail-fast: any non-zero exit aborts the bundle install.

**Presets** — curated groups of `defaults write` commands:

```bash
dotpkg_preset keyboard --key-repeat 2 --initial-key-repeat 15
dotpkg_preset finder
dotpkg_preset dock --icon-size 48 --auto-hide false
dotpkg_preset trackpad --enable-tap-to-click
dotpkg_preset screenshots --location ~/Downloads/screenshots
dotpkg_preset display --screensaver-idle 300
dotpkg_preset menubar --show-battery-percentage true
dotpkg_preset accent-color --value blue
dotpkg_preset spotlight
dotpkg_preset privacy --disable-analytics true
```

Accent color values: `graphite` `red` `orange` `yellow` `green` `blue` `purple` `pink` `multicolor`

**Hotkeys:**

```bash
dotpkg_hotkey_disable spotlight         # disables Cmd+Space / Cmd+Option+Space
dotpkg_hotkey_disable mission-control   # disables Ctrl+Up / Ctrl+Down

dotpkg_hotkey_set_corner tl 3   # top-left corner: show application windows
dotpkg_hotkey_set_corner br 10  # bottom-right corner: put display to sleep
```

Hot corner action values: `0`=none, `2`=mission-control, `3`=show-application-windows, `4`=desktop, `10`=put-display-to-sleep, `11`=launchpad, `14`=notification-center

**Dock:**

```bash
dotpkg_dock add "Visual Studio Code" "Figma" "iTerm"  # append apps
dotpkg_dock clear                                      # remove all apps
dotpkg_dock set "Visual Studio Code" "iTerm"           # replace dock contents
```

**Wallpaper and terminal:**

```bash
dotpkg_wallpaper ~/dotfiles/wallpapers/nord.png
dotpkg_terminal_import ~/dotfiles/themes/nord.terminal
```

**Machine-local overrides:**

Override individual preset values per machine without editing the bundle. Create `~/.dotpkg/presets/<category>.local.sh` — sourced **after** the preset runs, so your values win.

Example: bundle sets `KeyRepeat=2`, but you want `1` on this machine:

```bash
# ~/.dotpkg/presets/keyboard.local.sh
defaults write NSGlobalDomain KeyRepeat -int 1
```

The preset's other values (InitialKeyRepeat, auto-capitalize, etc.) remain unchanged. Only keys you explicitly override are replaced.

**Raw defaults:** `defaults.sh` can contain arbitrary bash. Presets and helpers are the recommended path for safety and idempotency, but nothing is restricted.

### extensions.txt

Editor extension IDs, one per line. dotpkg detects installed editors (VS Code, Cursor, Codium) and installs for each. Extensions unavailable in the marketplace emit a warning and are skipped; other failures (network, auth) abort the install.

```
arcticicestudio.nord-visual-studio-code
ms-python.python
redhat.vscode-yaml
github.copilot
```

### themes/

Files copied (not symlinked) into app-specific locations. Use for sandboxed apps or Group Containers where symlinks are rejected. Declare the destination in `bundle.info` via `theme_target`. Theme files are re-copied on every `dotpkg sync` — copy is unconditional and idempotent.

### requires.txt — dependencies

Other bundles this bundle depends on, one name per line. Dependencies are installed before the current bundle. Diamond dependencies (A needs B and C, B also needs C) are deduplicated — C installs exactly once. Circular dependencies are detected and skipped with a warning.

```
dev-base
shell-tools
```

Resolution order: local `bundles/` -> local `profiles/` -> user remotes (`~/.dotpkg/sources`) -> GitHub shorthand

---

## Profiles

A profile is a bundle with `type=profile` that contains only `requires.txt`. It represents a machine role.

`profiles/workstation/bundle.info`:
```
name=workstation
description=Full development workstation
type=profile
```

`profiles/workstation/requires.txt`:
```
personal
dev-tools
video-editor
```

Install a profile:

```bash
dotpkg init --profile workstation
# or, on an already-initialized machine:
dotpkg add workstation
```

The root bundle is always installed first regardless of profile. Listing `personal` in `requires.txt` is optional but documents the dependency explicitly.

---

## Bundle sources

Bundles are resolved in this order:

1. **Local** — `~/dotfiles/bundles/<name>/`
2. **Profiles** — `~/dotfiles/profiles/<name>/`
3. **User remotes** — git repos in `~/.dotpkg/sources` (trusted, no preview)
4. **GitHub shorthand** — `user/repo` fetched from GitHub (full preview + confirmation required)

### User remotes

Add a line to `~/.dotpkg/sources`:

```
tima/dotpkg-bundles
myorg/shared-bundles
git@github.internal:team/bundles.git
```

Pull updates:

```bash
dotpkg update
```

### GitHub shorthand

Install a bundle directly from a GitHub repo (the repo root must be the bundle):

```bash
dotpkg add someuser/nord-bundle
```

dotpkg shows a full preview of bundle.info, Brewfile, defaults.sh, extensions.txt, and requires.txt before asking for confirmation. Nothing is installed without explicit `y`.

---

## CLI reference

```
dotpkg init [--repo PATH] [--profile NAME] [-y]
```
Bootstrap a machine. Prompts for dotfiles repo path (default: `~/dotfiles`). Installs root bundle. Optionally installs a profile. `-y` skips interactive prompts.

```
dotpkg add <bundle>
```
Install a bundle by name or GitHub shorthand (`user/repo`). Root bundle installed first if not already present. Resolves and installs dependencies.

```
dotpkg sync
```
Re-apply all installed bundles. Idempotent — safe to run repeatedly.

```
dotpkg status [--json]
```
Show installed bundles and applied presets. `--json` for machine-readable output.

```
dotpkg list [--local | --remote]
```
List available bundles from all sources. `--local` shows only your dotfiles repo. `--remote` shows registered sources and cached GitHub bundles.

```
dotpkg update
```
Pull latest versions of remote bundles, then sync.

```
dotpkg create <name>
```
Scaffold a new bundle directory under `bundles/<name>/`.

```
dotpkg adopt --brew
```
Dump currently installed Homebrew packages, review, and assign to a bundle.

```
dotpkg adopt <file> --bundle <name> [-y]
```
Move a config file into a bundle's `stow/` package and immediately stow it, creating a symlink at the original location. File must be under `$HOME` and must not already be a symlink. Use `-y` to skip confirmation.

---

## Security Model

**Principle: Bundles configure apps, not the system.**

dotpkg enforces a trust-based security model:

**Personal bundles** (root bundle + local `bundles/`):
- Full access — can execute `defaults.sh` with all presets, helpers, and arbitrary bash
- You own this code, you control what runs

**Remote bundles** (user sources + GitHub shorthand):
- **defaults.sh is NOT executed** — no code execution from remote bundles
- Configure apps via `stow/` (config files), `extensions.txt` (extensions), `Brewfile` (packages), `themes/` (copied files)
- If a bundle needs `defaults write`, it documents commands in README — you review and add to your personal `defaults.sh` manually
- Zero remote code execution = zero attack surface

Installing a "VS Code" bundle from GitHub installs VS Code, stows config files, and installs extensions. It cannot change system keyboard settings, wipe your dock, set wallpaper, or execute arbitrary code.

See `SECURITY.md` for full details.

---

## AI interface

dotpkg is designed for AI agent consumption:

- `dotpkg status --json` — machine-readable installed state
- All commands support non-interactive flags (no prompts when scripted)
- `dotpkg help` — descriptive enough for an agent to discover capabilities

Example: an AI agent can query `dotpkg status --json` to check what tools are available before suggesting commands, or run `dotpkg add <bundle>` non-interactively as part of a setup flow.

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `DOTPKG_HOME` | `~/.dotpkg` | dotpkg tool and state directory |
| `DOTFILES_DIR` | `~/dotfiles` | dotfiles repo location (persisted to `~/.dotpkg/config` by init) |
| `STATE_FILE` | `$DOTPKG_HOME/state.json` | installed state (not git-tracked) |
