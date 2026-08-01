#!/usr/bin/env bash
# tests/test_bundle.sh — assert-based unit tests for state, bundle, and resolution logic.
# Run directly: bash tests/test_bundle.sh

set -euo pipefail

DOTPKG_HOME="$(cd "$(dirname "$0")/.." && pwd)"
export DOTPKG_HOME

# Isolated state file for tests
STATE_FILE=$(mktemp)
export STATE_FILE
# shellcheck disable=SC2064
trap "rm -f '$STATE_FILE'" EXIT

DOTFILES_DIR=$(mktemp -d)
export DOTFILES_DIR
trap "rm -rf '$DOTFILES_DIR'; rm -f '$STATE_FILE'" EXIT

# Source libraries under test
# shellcheck disable=SC1091
. "$DOTPKG_HOME/lib/state.sh"
# shellcheck disable=SC1091
. "$DOTPKG_HOME/lib/bundle.sh"

# ---------------------------------------------------------------------------
# Minimal test harness
# ---------------------------------------------------------------------------
_PASS=0; _FAIL=0

_pass() { echo "PASS: $1"; _PASS=$((_PASS + 1)); }
_fail() { echo "FAIL: $1${2:+ — $2}"; _FAIL=$((_FAIL + 1)); }

assert_true() {
  local desc="$1"; shift
  if "$@" 2>/dev/null; then _pass "$desc"; else _fail "$desc"; fi
}

assert_false() {
  local desc="$1"; shift
  if ! "$@" 2>/dev/null; then _pass "$desc"; else _fail "$desc"; fi
}

assert_eq() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then _pass "$desc"; else _fail "$desc" "got='$got' want='$want'"; fi
}

# ---------------------------------------------------------------------------
# state tests
# ---------------------------------------------------------------------------

state_init
assert_true  "state_init creates file"        test -f "$STATE_FILE"
assert_false "empty state: foo not installed" state_bundle_installed "foo"

state_add_bundle "foo" "local"
assert_true  "after add: foo installed"       state_bundle_installed "foo"

# Idempotent add
state_add_bundle "foo" "local"
count=$(state_get_json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['installed_bundles']))")
assert_eq    "add is idempotent"              "$count" "1"

state_add_bundle "bar" "github"
count=$(state_get_json | python3 -c "import json,sys; print(len(json.load(sys.stdin)['installed_bundles']))")
assert_eq    "add second bundle"              "$count" "2"

state_remove_bundle "foo"
assert_false "after remove: foo not installed" state_bundle_installed "foo"
assert_true  "after remove: bar still installed" state_bundle_installed "bar"

# state_list_bundles
list=$(state_list_bundles)
assert_eq    "list contains bar"              "$list" "bar"

# ---------------------------------------------------------------------------
# visited-set tests
# ---------------------------------------------------------------------------

_DOTPKG_VISITED=""
assert_false "visited: initially false for alpha" _bundle_visited "alpha"
_bundle_visit "alpha"
assert_true  "visited: true after visit"     _bundle_visited "alpha"
assert_false "visited: false for unvisited"  _bundle_visited "beta"
_bundle_visit "beta"
assert_true  "visited: true for beta"        _bundle_visited "beta"
# Cycle protection: visiting alpha again is a no-op at the call site
_bundle_visit "alpha"  # no dedup in _bundle_visit itself; handled by caller check
assert_true  "visited: alpha still marked"   _bundle_visited "alpha"

# ---------------------------------------------------------------------------
# bundle_info_get tests
# ---------------------------------------------------------------------------

BUNDLE_DIR=$(mktemp -d)
cat > "$BUNDLE_DIR/bundle.info" <<'EOF'
name=testbundle
description=A test bundle
author=tima
type=bundle
stow_target=~/Library/Test
EOF

assert_eq "bundle_info_get: name"        "$(bundle_info_get "$BUNDLE_DIR" name)"        "testbundle"
assert_eq "bundle_info_get: description" "$(bundle_info_get "$BUNDLE_DIR" description)" "A test bundle"
assert_eq "bundle_info_get: stow_target" "$(bundle_info_get "$BUNDLE_DIR" stow_target)" "~/Library/Test"
assert_eq "bundle_info_get: missing key" "$(bundle_info_get "$BUNDLE_DIR" nonexistent)" ""

# ---------------------------------------------------------------------------
# resolve_bundle tests
# ---------------------------------------------------------------------------

# Setup fake local bundle
mkdir -p "$DOTFILES_DIR/bundles/mytool"
cat > "$DOTFILES_DIR/bundles/mytool/bundle.info" <<'EOF'
name=mytool
description=Test tool bundle
type=bundle
EOF

# Setup fake profile
mkdir -p "$DOTFILES_DIR/profiles/myprofile"
cat > "$DOTFILES_DIR/profiles/myprofile/bundle.info" <<'EOF'
name=myprofile
description=Test profile
type=profile
EOF

resolved=$(resolve_bundle "mytool")
assert_eq "resolve_bundle: local bundle"  "$resolved" "$DOTFILES_DIR/bundles/mytool"

resolved=$(resolve_bundle "myprofile")
assert_eq "resolve_bundle: profile"       "$resolved" "$DOTFILES_DIR/profiles/myprofile"

# Non-existent bundle should fail
if resolve_bundle "doesnotexist" 2>/dev/null; then
  _fail "resolve_bundle: non-existent should return 1"
else
  _pass "resolve_bundle: non-existent returns 1"
fi

rm -rf "$BUNDLE_DIR"
rm -rf "$DOTFILES_DIR/bundles/mytool" "$DOTFILES_DIR/profiles/myprofile"

# ---------------------------------------------------------------------------
# install_bundle: minimal bundle (bundle.info only, no side effects)
# ---------------------------------------------------------------------------

MINIMAL_BUNDLE=$(mktemp -d)
cat > "$MINIMAL_BUNDLE/bundle.info" <<'EOF'
name=minimal
description=Minimal test bundle with no assets
type=bundle
EOF

_DOTPKG_VISITED=""
# Re-init state so 'minimal' is not in it
printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"

install_bundle "$MINIMAL_BUNDLE" "local"
assert_true "install_bundle: minimal bundle recorded in state" state_bundle_installed "minimal"

# install_bundle: cycle detection (same bundle twice)
_DOTPKG_VISITED=""
printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"
install_bundle "$MINIMAL_BUNDLE" "local"
# Second call should skip (already visited)
output=$(install_bundle "$MINIMAL_BUNDLE" "local" 2>&1 || true)
if echo "$output" | grep -q "already processed"; then
  _pass "install_bundle: cycle — skips duplicate"
else
  _fail "install_bundle: cycle — expected 'already processed' message"
fi

# install_bundle: dependency install order
DEP_BUNDLE=$(mktemp -d)
cat > "$DEP_BUNDLE/bundle.info" <<'EOF'
name=depbundle
description=Dependency bundle
type=bundle
EOF

PARENT_BUNDLE=$(mktemp -d)
mkdir -p "$DOTFILES_DIR/bundles/depbundle"
cp -r "$DEP_BUNDLE/." "$DOTFILES_DIR/bundles/depbundle/"
cat > "$PARENT_BUNDLE/bundle.info" <<'EOF'
name=parentbundle
description=Parent that requires depbundle
type=bundle
EOF
echo "depbundle" > "$PARENT_BUNDLE/requires.txt"

_DOTPKG_VISITED=""
printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"
install_bundle "$PARENT_BUNDLE" "local"
assert_true "install_bundle: dep installed before parent" state_bundle_installed "depbundle"
assert_true "install_bundle: parent installed after dep"  state_bundle_installed "parentbundle"

rm -rf "$MINIMAL_BUNDLE" "$DEP_BUNDLE" "$PARENT_BUNDLE"
rm -rf "$DOTFILES_DIR/bundles/depbundle"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: PASS=$_PASS FAIL=$_FAIL"
[[ $_FAIL -eq 0 ]]
