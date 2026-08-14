# Dotfiles System -- How It Works

> **LEGACY DOCUMENTATION**
>
> This document describes the legacy dotfiles system (pre-dotpkg). It documents manual setup workflows that have been superseded by the dotpkg CLI tool. Refer to [README.md](../README.md) for current dotpkg documentation.

## Overview

The system lives in `~/dotfiles/`, a Git repository that stores configuration files and shell scripts. Together they automate the setup of a new Mac from a blank state and keep configurations in sync across machines. The repo is hosted on GitHub at `tima/dotfiles`.

The system has four layers: a package manifest, a symlink manager, orchestration scripts, and a system defaults script. Each handles a different part of the problem.


## Core Tools

### Homebrew

The system's package installer. Everything the Mac needs -- CLI tools, GUI apps, fonts, casks -- is installed through Homebrew. Nothing is installed manually or downloaded from the web.

### GNU Stow

The symlink manager. Stow takes a directory of config files and creates symlinks from the expected locations (e.g., `~/.zshrc`, `~/.gitconfig`) back to the files in the repo. This means the repo is the single source of truth -- edits to `~/.zshrc` actually edit `~/dotfiles/zsh/.zshrc` because it's a symlink.

Stow uses a convention: each top-level directory in the repo is a "package." The directory structure inside the package mirrors where the files should land relative to the target directory (default: `$HOME`). For example:

```
~/dotfiles/zsh/.zshrc       -->  symlinked to  ~/.zshrc
~/dotfiles/git/.gitconfig    -->  symlinked to  ~/.gitconfig
~/dotfiles/tmux/.tmux.conf   -->  symlinked to  ~/.tmux.conf
```

Some apps store configs outside `$HOME` (e.g., in `~/Library/Application Support/`). For those, Stow is invoked with `--target=` pointing to the correct location.

Stow is idempotent -- running it again on an already-stowed package is a no-op.

### `defaults write`

macOS stores application and system preferences in plist files accessible via the `defaults` command. The system uses `defaults write` to set system-wide preferences (keyboard speed, Finder behavior, Dock layout, etc.) and per-app settings (e.g., telling iTerm2 to load preferences from the dotfiles folder).


## Key Files

### `Brewfile`

A declarative manifest of every package, cask, and font the system needs. Homebrew reads it via `brew bundle` and installs anything missing. Acts as the single inventory of what goes on the machine. Idempotent -- already-installed items are skipped.

### `bootstrap.sh`

The full setup orchestrator. Designed to run on a blank Mac and produce a fully configured environment. Runs in this order:

1. Acquires sudo and keeps it alive for the duration
2. Installs Homebrew if missing, configures the Apple Silicon path
3. Runs `brew bundle` against the Brewfile
4. Runs Stow for standard packages (zsh, vim, git, tmux, starship)
5. Runs Stow with custom targets for apps that store configs in `~/Library/...`
6. Installs editor extensions from a text file list
7. Initializes any runtime engines (e.g., Podman VM)
8. Copies theme files into app-specific locations where Stow can't reach (sandboxed apps, Group Containers)
9. Runs `macos.sh` for system defaults
10. Configures iTerm2 to load preferences from the dotfiles folder

Requires sudo. Not idempotent in every section (some steps use `rm -f` before re-linking), but safe to re-run.

### `install.sh`

A lighter, incremental version of bootstrap. Meant for day-to-day use after the initial setup. It:

1. Verifies Homebrew exists at the Apple Silicon path
2. Verifies Stow is installed (installs it if missing)
3. Runs `brew bundle` to pick up any new Brewfile entries
4. Re-stows all standard packages

Does not require sudo. Does not touch editor extensions, app sandboxes, or system defaults. Safe and fast to run repeatedly.

### `macos.sh`

A script of `defaults write` commands that configure macOS system preferences: keyboard repeat rate, Finder settings, Dock behavior, screenshot location, Spotlight shortcuts, trackpad settings, display/sleep, menu bar items, wallpaper, and terminal profiles. Closes System Settings before running to prevent conflicts.

Requires a logout or restart for some changes to take effect.

> **Terminology Note**
>
> In this legacy documentation, composable units are called "stow packages." In the current dotpkg system, these are called "bundles." The concepts are similar—both are collections of configuration files, dependencies, and metadata—but bundles are more flexible and support more features (Brewfiles, extensions, themes, presets). If you're reading this to understand the old system, use "stow package." If you're using dotpkg, refer to the [README](../README.md) which uses the term "bundle."

## Stow Package Types

The repo uses two patterns depending on where the app expects its config:

**Standard packages** -- Config files that live in `$HOME`. Stow runs with no flags:
```
stow zsh        # ~/dotfiles/zsh/.zshrc  -->  ~/.zshrc
stow git        # ~/dotfiles/git/.gitconfig  -->  ~/.gitconfig
```

**Custom-target packages** -- Config files that live in `~/Library/Application Support/` or macOS sandbox containers. Stow runs with `--target=`:
```
stow --target="$HOME/Library/Application Support/Code/User" vscode
stow --target="$HOME/Library/Containers/app.cyan.markedit/Data/Documents" markedit
```

**Copy-only configs** -- Some sandboxed apps or Group Containers don't work well with symlinks. These use `cp` instead of Stow and `defaults write` to register the file with the app.


## Workflow

### New machine, existing dotfiles repo (day zero)

A GitHub Gist hosts a one-liner that curls down and runs a bootstrap script. That script clones the dotfiles repo and runs `bootstrap.sh`. The only manual step is approving Apple's Command Line Developer Tools popup the first time.

```
curl one-liner --> clones repo --> bootstrap.sh --> fully configured Mac
```

This is the primary use case the system was built for. It assumes the `~/dotfiles/` repo already exists on GitHub with a populated Brewfile, stow packages, and bootstrap script.

### New machine, no dotfiles repo (starting from scratch)

The system has no tooling for this case. On a brand-new Mac with no existing dotfiles repo, everything must be set up manually:

1. Install Homebrew
2. `brew install stow git`
3. `mkdir ~/dotfiles && cd ~/dotfiles && git init`
4. Create the first stow package (e.g., `mkdir -p zsh` and create `zsh/.zshrc`)
5. Run `stow zsh` to symlink it into place
6. Create a `Brewfile` by hand or by auditing what you install as you go
7. Write `bootstrap.sh` and `macos.sh` incrementally as you configure the machine
8. Push to GitHub

There is no scaffold command, no init script, and no way to generate a Brewfile or bootstrap script from the current machine state. The user builds the repo organically as they set up the machine.

**Future: The new system should provide an `init` command that scaffolds a new dotfiles repo -- creating the directory structure, initial Brewfile, bootstrap script, and first stow packages from a template or by detecting what's on the machine.**

**Future: Integrate `gum` (Charmbracelet) for interactive prompts in dotfiles scripts. Replaces raw `read`/`select` with polished UI components -- fuzzy pickers, confirmation dialogs, multi-select lists, spinners. Natural fit for a `dotpkg` CLI. Add `brew "gum"` to Brewfile when the time comes.**

### Existing machine, adopting into the system

For a Mac that already has unmanaged dotfiles (config files sitting directly in `$HOME`), each file must be migrated manually:

1. Create the stow package directory: `mkdir -p ~/dotfiles/zsh`
2. Move the config file into it: `mv ~/.zshrc ~/dotfiles/zsh/.zshrc`
3. Run `stow zsh` to create the symlink back to `~/.zshrc`
4. Verify the symlink works: `ls -la ~/.zshrc` should point to `dotfiles/zsh/.zshrc`
5. Repeat for every config file to manage

For apps with configs in `~/Library/Application Support/`, the process is the same but requires `--target=` on the stow command and more careful path mirroring inside the package directory.

To capture the installed packages: `brew list` and `brew list --cask` show what Homebrew has installed, but there is no command to generate a Brewfile from the current state. Each entry must be added to the Brewfile manually.

No part of this adoption workflow is automated. The system assumes you already have a repo -- it has no "import" or "adopt" capability.

### Ongoing changes

1. Edit the config file directly (e.g., `~/.zshrc`, which is a symlink to `~/dotfiles/zsh/.zshrc`)
2. Changes are automatically in the repo because of the symlink
3. `git commit` and `git push` from `~/dotfiles/`
4. On another machine: `git pull` and optionally run `install.sh` if Brewfile changed

### Adding a new tool

1. Add the brew formula or cask to `Brewfile`
2. If it has config files: create a new Stow package directory, place config files in it mirroring the expected path structure
3. Add the Stow command to `bootstrap.sh` (and `install.sh` if it's a standard package)
4. Commit and push

### Machine-specific overrides

The `.zshrc` sources `~/.zshrc.local` if it exists. This file is not tracked in git and allows per-machine environment variables, paths, or aliases without polluting the shared config.

There is no equivalent for `macos.sh` -- system defaults are all-or-nothing. **Future: The new system should support a `macos.sh.local` pattern, where `macos.sh` sources a local override file if present, allowing per-machine system defaults (e.g., different display settings, work vs. personal Dock layouts) without forking the shared script.**
