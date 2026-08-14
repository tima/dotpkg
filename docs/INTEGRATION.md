# dotpkg Phase 2 Integration Testing

Phase 2 CLI commands (init, add, sync, status, list, update, create, adopt) are implemented and unit-tested (24/24 assertions pass in [tests/test_bundle.sh](tests/test_bundle.sh)).

Manual integration tests can be run against a real or mock dotfiles repo:

## Setup

1. Create a test dotfiles repo:
```bash
TEST_DIR=$(mktemp -d)
mkdir -p "$TEST_DIR/dotfiles/bundles"
cat > "$TEST_DIR/dotfiles/bundle.info" <<EOF
name=personal
description=Personal settings
author=test
type=bundle
EOF
```

2. Initialize dotpkg against test repo:
```bash
export DOTFILES_DIR="$TEST_DIR/dotfiles"
export DOTPKG_HOME="$TEST_DIR/.dotpkg"
bash /path/to/dotfiles-mgr/bootstrap.sh
```

Or manually (without full bootstrap):
```bash
mkdir -p "$DOTPKG_HOME/lib"
cp /path/to/dotfiles-mgr/dotpkg "$DOTPKG_HOME/"
cp /path/to/dotfiles-mgr/lib/* "$DOTPKG_HOME/lib/"
chmod +x "$DOTPKG_HOME/dotpkg"

DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" init --repo "$TEST_DIR/dotfiles" -y
```

## Test Cases

### init
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" init --repo "$TEST_DIR/dotfiles" --profile workstation -y
```
Expected: state.json created with personal + profile bundles; config file written.

### add
```bash
# Create a test bundle
mkdir -p "$TEST_DIR/dotfiles/bundles/devtools"
cat > "$TEST_DIR/dotfiles/bundles/devtools/bundle.info" <<EOF
name=devtools
description=Dev tools
type=bundle
EOF

DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" add devtools
```
Expected: devtools added to state.json.

### status
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" status
```
Expected: Lists installed bundles.

### status --json
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" status --json | python3 -m json.tool
```
Expected: Valid JSON with installed_bundles array.

### list
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" list
```
Expected: Shows local bundles and profiles.

### create
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" create mynewbundle
```
Expected: Creates bundles/mynewbundle with scaffold bundle.info.

### sync
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" sync
```
Expected: Re-applies all installed bundles; idempotent.

## Notes

- Automated integration tests (no system side-effects): `bash tests/test_integration_phase2.sh` — 34 assertions covering init, add, status, list, create, sync, diamond deps, idempotency, profiles
- Actual Brewfile installs require brew on PATH
- stow operations require stow installed (comes with bootstrap.sh)
- GitHub shorthand bundles (user/repo) require curl + git + gum for preview confirmation
- Full end-to-end test needs a real machine or VM (stow, brew bundle, defaults write all change system state)

## Phase 3: Bundle Sources and Caching

Phase 3 implements bundle source resolution (cache keys, sources, GitHub shorthand). Automated tests: 20 assertions (test_phase3.sh).

### Setup

1. Create test source repos:
```bash
mkdir -p "$TEST_DIR/.dotpkg/cache/sources"
# Create a git repo to act as a "source"
SOURCE_REPO="$TEST_DIR/test-source-repo"
mkdir -p "$SOURCE_REPO/bundles/test-bundle"
cat > "$SOURCE_REPO/bundles/test-bundle/bundle.info" <<EOF
name=test-bundle
description=Test bundle from source
author=test
type=bundle
EOF
cd "$SOURCE_REPO" && git init && git add . && git commit -m "init" && cd -
```

2. Register the source:
```bash
mkdir -p "$DOTPKG_HOME"
echo "$SOURCE_REPO" > "$DOTPKG_HOME/sources"
```

### Test Cases

#### dotpkg list --remote
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" list --remote
```
Expected: Shows source bundles from cache (not found until first update).

#### dotpkg update
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" update
```
Expected: Pulls source repos into cache, then syncs all installed bundles.

#### dotpkg add from source
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" add test-bundle
```
Expected: Resolves test-bundle from source cache, installs it.

#### GitHub shorthand (user/repo)
```bash
# This requires curl + git + gum for preview (skip in automated tests)
# Manual test: DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
#   "$DOTPKG_HOME/dotpkg" add someuser/test-bundle
```
Expected: Shows preview of bundle.info, Brewfile, defaults.sh, etc. Requires explicit `y` confirmation.

## Phase 4: Presets and Helpers

Phase 4 implements system preset application, per-machine overrides, and state tracking. Automated tests: 50 assertions (test_helpers.sh).

### Setup

1. Create a bundle with defaults.sh using presets:
```bash
mkdir -p "$TEST_DIR/dotfiles/bundles/preset-test"
cat > "$TEST_DIR/dotfiles/bundles/preset-test/bundle.info" <<EOF
name=preset-test
description=Test presets
type=bundle
EOF

cat > "$TEST_DIR/dotfiles/bundles/preset-test/defaults.sh" <<EOF
#!/bin/bash
dotpkg_preset keyboard --key-repeat 2 --initial-key-repeat 15
dotpkg_preset finder
EOF
```

2. Create a per-machine override:
```bash
mkdir -p "$DOTPKG_HOME/presets"
cat > "$DOTPKG_HOME/presets/keyboard.local.sh" <<EOF
#!/bin/bash
# Override: use faster repeat rate on this machine
defaults write NSGlobalDomain KeyRepeat -int 1
EOF
```

### Test Cases

#### Preset application
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" add preset-test
```
Expected: Runs defaults.sh, applies keyboard and finder presets, records in state.json.

#### state.json includes applied presets
```bash
DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" status --json | python3 -m json.tool
```
Expected: Output includes `installed_presets` array with `["keyboard", "finder"]`.

#### Per-machine override sourced
When preset runs, per-machine override `~/.dotpkg/presets/<category>.local.sh` is sourced after the built-in preset. In this test setup, the local override will run and set a different KeyRepeat value, overriding the preset default.

Expected: Preset applies, then local override runs (you would verify on a real machine via `defaults read NSGlobalDomain KeyRepeat`).

#### Stow paths tracked in state
When a bundle is installed, top-level files/dirs in its `stow/` directory are recorded:
```bash
# Create a bundle with stow contents
mkdir -p "$TEST_DIR/dotfiles/bundles/config-test/stow/.config/app"
echo "config" > "$TEST_DIR/dotfiles/bundles/config-test/stow/.config/app/config.toml"
cat > "$TEST_DIR/dotfiles/bundles/config-test/bundle.info" <<EOF
name=config-test
description=Config files
type=bundle
EOF

DOTFILES_DIR="$TEST_DIR/dotfiles" DOTPKG_HOME="$DOTPKG_HOME" \
  "$DOTPKG_HOME/dotpkg" add config-test
```

Expected: `stow_paths` in state.json includes `[".config"]` (the top-level entry in stow/).

## Notes (continued)

- Automated integration tests for Phase 3: `bash tests/test_phase3.sh` — covers bundle source resolution, caching, dotpkg update, and GitHub shorthand
- Automated integration tests for Phase 4: `bash tests/test_helpers.sh` — covers preset application, state tracking, and per-machine overrides
