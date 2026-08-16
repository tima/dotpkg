# Bundle Authoring Guide

Create a new bundle scaffold:

```bash
dotpkg create my-bundle
```

This creates `bundles/my-bundle/` with a starter `bundle.info` and `stow/` dir. Add files as needed — all are optional except `bundle.info`.

## bundle.info

Plain key-value pairs. No parser needed.

```text
name=dev-tools
description=Development tools and configuration
author=yourname
type=bundle
```

`type` is `bundle` (default) or `profile`. The `name` field must match the directory name for local bundles.

Optional:

```text
stow_target=~/Library/Application Support/Code/User
```

If `stow_target` is omitted, stow targets `$HOME`. If a bundle needs multiple stow targets, split it into separate bundles.

For theme file destinations:

```text
theme_target=~/Library/Application Support/SomeApp/themes
```

## Brewfile

Standard Homebrew Bundle format. dotpkg runs `brew bundle` without `--upgrade` — adds missing formulas, never upgrades existing ones. Version management is separate.

```bash
brew "ripgrep"
brew "fd"
brew "python@3.12"
cask "visual-studio-code"
cask "docker"
tap "homebrew/cask-fonts"
cask "font-jetbrains-mono-nerd-font"
```

Note: dotpkg runs `brew bundle` without `--upgrade` — it adds missing packages but never upgrades existing ones. This prevents surprise major version bumps.

## stow/ — config files

A directory tree that mirrors the target directory (default: `$HOME`). GNU Stow creates symlinks from the target into your bundle. dotpkg runs a conflict pre-check before symlinking. If a file already exists and is not managed by stow, the install aborts with a clear error.

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

## defaults.sh — presets and helpers

A shell script sourced (not executed as a subprocess) into dotpkg's process. This provides preset and helper functions without requiring imports. Execution uses fail-fast mode: any non-zero exit aborts the bundle install.

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

## extensions.txt

Editor extension IDs, one per line. dotpkg detects installed editors (VS Code, Cursor, Codium) and installs for each. Extensions unavailable in the marketplace emit a warning and are skipped; other failures (network, auth) abort the install.

**Per-editor files:** Use separate files when marketplaces differ:
- `extensions.vscode.txt` — VS Code only
- `extensions.cursor.txt` — Cursor only
- `extensions.codium.txt` — Codium only
- `extensions.txt` — fallback for any editor without a specific file

```text
# extensions.vscode.txt
arcticicestudio.nord-visual-studio-code
ms-python.python
redhat.vscode-yaml
github.copilot

# extensions.cursor.txt
saoudrizp.claude-dev
```

Find extension IDs on the VS Code marketplace (copy from the ID field). For multi-editor bundles, use separate files when marketplaces differ: `extensions.vscode.txt` for VS Code, `extensions.cursor.txt` for Cursor, `extensions.codium.txt` for Codium — each marketplace has different IDs.

## themes/

Files copied (not symlinked) into app-specific locations. Use for sandboxed apps or Group Containers where symlinks are rejected. Declare the destination in `bundle.info` via `theme_target`. Theme files are re-copied on every `dotpkg sync` — copy is unconditional and idempotent.

## requires.txt — dependencies

Other bundles this bundle depends on, one name per line. Dependencies are installed before the current bundle. Diamond dependencies (A needs B and C, B also needs C) are deduplicated — C installs exactly once. Circular dependencies are detected and skipped with a warning.

```
dev-base
shell-tools
```

Resolution order: local `bundles/` -> local `profiles/` -> user remotes (`~/.dotpkg/sources`) -> GitHub shorthand

## README.md — Documentation

Optional, but recommended. A human-readable description of what the bundle does, what it installs, and any manual setup required (especially for remote bundles where `defaults.sh` is not executed).

**Suggested structure** (not required):

```markdown
# Bundle Name

## What This Bundle Does
Brief description of the bundle's purpose.

## What Gets Installed
- List of formulas, casks, or tools
- Configuration details

## Prerequisites
Any setup required before installation (if any).

## Manual Setup (for remote bundles)
If this bundle requires `defaults write` commands or other manual steps, document them here. Users will review and add them to their personal `defaults.sh` if needed.

Example:
    defaults write com.company.app "Key" -string "value"
```

Write what your bundle actually needs. This template is a starting point, not a requirement.


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
