# CLI Reference

Full command reference with flags and arguments.

```
dotpkg init [--repo PATH] [--profile NAME]
            [-y|--non-interactive]
```
Bootstrap a machine. Prompts for dotfiles repo path (default: `~/dotfiles`). Installs root bundle. Optionally installs a profile. `-y` or `--non-interactive` skips interactive prompts.

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
dotpkg adopt <file> --bundle|-b <name>
            [-y|--non-interactive]
```
Move a config file into a bundle's `stow/` package and immediately stow it, creating a symlink at the original location. File must be under `$HOME` and must not already be a symlink. Use `-y` or `--non-interactive` to skip confirmation.

```
dotpkg --version
```
Show dotpkg version.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DOTPKG_HOME` | `~/.dotpkg` | dotpkg tool and state directory |
| `DOTFILES_DIR` | `~/dotfiles` | dotfiles repo location (persisted to `~/.dotpkg/config` by init) |
| `STATE_FILE` | `$DOTPKG_HOME/state.json` | installed state (not git-tracked) |
| `DOTPKG_CONFIG` | `$DOTPKG_HOME/config` | dotpkg config file (set by init, persists dotfiles_dir path) |
