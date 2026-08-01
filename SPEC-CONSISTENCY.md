# Spec Consistency Check — 2026-08-01

## Verified Consistent

**Bootstrap flow** (spec line 36-46):
- ✓ Xcode CLT install
- ✓ Homebrew install
- ✓ `brew install stow gum`
- ✓ Clone to ~/.dotpkg/
- ✓ Symlink to /usr/local/bin/dotpkg
- ✓ Shell profile detection (fixed: now uses case statement, handles bash/zsh/fallback)

**Presets** (spec line 273-285):
- ✓ All categories implemented: keyboard, trackpad, dock, finder, screenshots, display, menubar, accent-color, spotlight, privacy
- ✓ Parameter signatures match spec
- ✓ spotlight preset is no-op (matches spec TBD note)

**Helpers** (spec line 287-293):
- ✓ dotpkg_hotkey_disable
- ✓ dotpkg_hotkey_set_corner
- ✓ dotpkg_dock add
- ✓ dotpkg_wallpaper
- ✓ dotpkg_terminal_import

**CLI commands** (spec line 338-431):
- ✓ init, add, sync, status, list, update, create, adopt
- ✓ adopt --brew mode
- ✓ adopt <file> --bundle <name> mode

**State schema** (spec line 316-332):
- ✓ installed_bundles: name, source, installed_at, stow_paths
- ✓ installed_presets

**Bundle resolution** (spec line 247-253):
- ✓ Local → User remotes → GitHub shorthand
- ✓ Implementation adds root bundle name lookup (step 0) and profiles tier between local/remote — not in spec but necessary for profiles to work

## Spec Ambiguities (not errors)

1. **Profile resolution tier** — spec says "local directory" but doesn't distinguish bundles/ vs profiles/. Implementation treats profiles/ as separate tier after bundles/, before remotes. Sensible, not documented.

2. **Root bundle name resolution** — spec doesn't say root bundle can be resolved by name (e.g., "personal" in profile requires.txt). Implementation added this (resolve_bundle step 0) to make profiles work. Should be documented.

3. **Gum fallback** — spec line 498 says "gum as hard dependency vs graceful fallback" is TBD. Implementation has full fallback (lib/prompt.sh). More complete than spec, not inconsistent.

## No Inconsistencies Found

Code faithfully implements spec as written. The three items above are implementation decisions for underspecified areas, all reasonable.
