# dotpkg

macOS machine setup and dotfiles manager. Packages Homebrew formulas, config files, editor extensions, themes, and system preferences into composable units called **bundles**. Go from a blank Mac to a fully configured system with a single curl command.

Zero runtime dependencies beyond what ships with macOS — everything else is bootstrapped.

---

## Table of Contents

- [Concepts](#concepts)
- [Bootstrap: new machine](#bootstrap-new-machine)
- [Existing machine](#existing-machine)
- [Your dotfiles repo](#your-dotfiles-repo)
- [Quick Start: Creating Bundles](#quick-start-creating-bundles)
- [Next Steps](#next-steps)
- [Notes for AI Agents](#notes-for-ai-agents)
- [Glossary](#glossary)

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
# Replace YOUR_USER with your GitHub username, dotpkg with your repo name
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/dotpkg/main/bootstrap.sh | bash
```

With a profile:

```bash
# Replace YOUR_USER with your GitHub username, dotpkg with your repo name
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

## Quick Start: Creating Bundles

Create a bundle scaffold:

```bash
dotpkg create my-bundle
```

This creates `bundles/my-bundle/` with starter files. Bundles can contain:
- `bundle.info` (required) — metadata
- `Brewfile` — Homebrew packages
- `stow/` — config files (symlinked)
- `defaults.sh` — macOS preferences
- `extensions.txt` — editor extensions
- `themes/` — theme files (copied)
- `requires.txt` — bundle dependencies

See [docs/bundle-authoring.md](docs/bundle-authoring.md) for the full guide.

---

## Next Steps

- **[Bundle Authoring Guide](docs/bundle-authoring.md)** — Full reference for creating bundles and profiles
- **[CLI Reference](docs/cli-reference.md)** — All commands, flags, and environment variables
- **[Bundle Sources](docs/bundle-sources.md)** — Local bundles, remote sources, and GitHub shorthand
- **[Security Model](docs/security.md)** — Trust model and remote bundle restrictions

---

## Notes for AI Agents

dotpkg is designed for machine-readable consumption:

- `dotpkg status --json` outputs machine-readable installed state
- All commands support non-interactive flags (no prompts when scripted)
- `dotpkg help` provides descriptive output for capability discovery

Example: an AI agent can query `dotpkg status --json` to check what tools are available before suggesting commands, or run `dotpkg add <bundle>` non-interactively as part of a setup flow.

---

## Glossary

**Adopt** — Importing existing machine state into dotpkg management (generating a Brewfile or moving a config file into a bundle).

**Bootstrap** — Going from a stock Mac to a dotpkg-managed machine via a curl one-liner.

**Brewfile** — Homebrew Bundle manifest listing packages, casks, and taps.

**Bundle** — A directory with assets to install on a machine (configs, Brewfile, extensions, themes, presets, dependencies).

**Bundle resolution** — The process of finding a bundle: checks local bundles → profiles → registered sources → GitHub shorthand.

**Defaults write** — macOS command for setting system preferences and app configurations.

**Extensions** — Editor extensions (VS Code, Cursor, Codium) installed via marketplace IDs.

**GNU Stow** — Symlink manager that creates links from config directories into their expected locations.

**GitHub shorthand** — A user/repo reference that resolves to a single GitHub repository (e.g., user/dotpkg-bundle).

**Homebrew** — macOS package manager.

**Installed** — A bundle that has been applied to the current machine; tracked in state.json.

**Preset** — A named, built-in group of `defaults write` commands (keyboard, finder, dock, etc.).

**Profile** — A bundle whose only job is listing other bundles in requires.txt; represents a machine identity or role.

**Root bundle** — The dotfiles repo root itself, treated as a bundle; always installed first.

**Source** — A git repository registered in ~/.dotpkg/sources as a trusted provider of bundles.

**State** — The installed bundles and applied presets on a machine, tracked in ~/.dotpkg/state.json.

**Stow_check** — Pre-check before symlinking to detect conflicts with existing files.

**Stow_target** — Specifies where GNU Stow should create symlinks (default: $HOME); used in bundle.info.

**Sync** — Re-applying all installed bundles to the current machine; idempotent.

**Theme_target** — Specifies where theme files should be copied (for sandboxed apps).

**Visited-set** — Internal tracking mechanism used during bundle dependency traversal to prevent circular dependencies.
