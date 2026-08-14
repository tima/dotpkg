# Security Model

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
