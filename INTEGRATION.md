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
