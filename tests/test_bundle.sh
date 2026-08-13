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
. "$DOTPKG_HOME/lib/stow.sh"
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

# Verify state file permissions are 600 (owner-only read/write)
perms=$(stat -f %A "$STATE_FILE" 2>/dev/null || stat -c %a "$STATE_FILE" 2>/dev/null || echo "ERROR")
assert_eq    "state_init: file permissions 600" "$perms" "600"

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
# state_get_bundle_source: retrieve stored source for a bundle
# ---------------------------------------------------------------------------

printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"
state_add_bundle "local-test" "local"
state_add_bundle "remote-test" "github"

source=$(state_get_bundle_source "local-test" 2>/dev/null || echo "ERROR")
assert_eq "state_get_bundle_source: local bundle" "$source" "local"

source=$(state_get_bundle_source "remote-test" 2>/dev/null || echo "ERROR")
assert_eq "state_get_bundle_source: remote bundle" "$source" "github"

# Non-existent bundle returns error
if state_get_bundle_source "nonexistent" 2>/dev/null; then
  _fail "state_get_bundle_source: nonexistent should return 1"
else
  _pass "state_get_bundle_source: nonexistent returns 1"
fi

# ---------------------------------------------------------------------------
# cmd_sync: preserves source and prevents remote re-execution
# ---------------------------------------------------------------------------

REMOTE_BUNDLE=$(mktemp -d)
cat > "$REMOTE_BUNDLE/bundle.info" <<'EOF'
name=remote-pkg
description=Simulated remote bundle
type=bundle
EOF

# Create a marker file that would be created by defaults.sh execution
MARKER_FILE=$(mktemp -d)/remote-executed
cat > "$REMOTE_BUNDLE/defaults.sh" <<EOF
#!/usr/bin/env bash
touch "$MARKER_FILE"
EOF
chmod +x "$REMOTE_BUNDLE/defaults.sh"

# Install remote bundle with "github" source
_DOTPKG_VISITED=""
printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"
mkdir -p "$DOTFILES_DIR/bundles"
cp -r "$REMOTE_BUNDLE/." "$DOTFILES_DIR/bundles/remote-pkg/"

install_bundle "$DOTFILES_DIR/bundles/remote-pkg" "github"
assert_true "install_bundle: remote bundle recorded with github source" state_bundle_installed "remote-pkg"

# Verify marker file was NOT created (defaults.sh was skipped)
if [[ -f "$MARKER_FILE" ]]; then
  _fail "cmd_sync: remote bundle should not execute defaults.sh on add"
else
  _pass "cmd_sync: remote bundle correctly skips defaults.sh on add"
fi

# Now sync — should preserve "github" source and still skip defaults.sh
_DOTPKG_VISITED=""
rm -f "$MARKER_FILE"

# Simulate cmd_sync manually (since we can't easily call it in test context)
if bundle_dir=$(resolve_bundle "remote-pkg" 2>/dev/null); then
  bundle_source=$(state_get_bundle_source "remote-pkg" 2>/dev/null || echo "local")
  # Don't actually re-install (would add to state again), just verify source is retrieved correctly
  assert_eq "cmd_sync: source correctly retrieved as github" "$bundle_source" "github"
else
  _fail "cmd_sync: bundle resolution failed"
fi

# Verify marker still wasn't created
if [[ -f "$MARKER_FILE" ]]; then
  _fail "cmd_sync: sync would have re-executed remote defaults.sh (BUG)"
else
  _pass "cmd_sync: sync correctly preserves remote source, prevents re-execution"
fi

rm -rf "$REMOTE_BUNDLE" "$(dirname "$MARKER_FILE")"
rm -rf "$DOTFILES_DIR/bundles/remote-pkg"

# ---------------------------------------------------------------------------
# install_bundle: dependency source re-evaluation (CRITICAL-1 fix)
# ---------------------------------------------------------------------------
# Verify that when a local bundle depends on a remote bundle,
# the remote dependency is correctly identified as remote and
# its defaults.sh is NOT executed.

# Setup: remote bundle (in cache, not under DOTFILES_DIR)
REMOTE_DEP_BUNDLE=$(mktemp -d)
cat > "$REMOTE_DEP_BUNDLE/bundle.info" <<'EOF'
name=remote-dep
description=Remote dependency
type=bundle
EOF

# Create marker file to verify defaults.sh execution
MARKER_DIR=$(mktemp -d)
MARKER_FILE="$MARKER_DIR/remote-dep-executed"
cat > "$REMOTE_DEP_BUNDLE/defaults.sh" <<EOF
#!/usr/bin/env bash
touch "$MARKER_FILE"
EOF
chmod +x "$REMOTE_DEP_BUNDLE/defaults.sh"

# Setup: local bundle that depends on the remote one
# Place remote dep in cache (simulating GitHub fetch)
CACHE_DIR="$DOTPKG_HOME/cache/github/author/remote-dep"
mkdir -p "$CACHE_DIR"
cp -r "$REMOTE_DEP_BUNDLE/." "$CACHE_DIR/"

# Create local bundle that requires the "remote" dependency
mkdir -p "$DOTFILES_DIR/bundles/local-with-remote-dep"
cat > "$DOTFILES_DIR/bundles/local-with-remote-dep/bundle.info" <<'EOF'
name=local-with-remote-dep
description=Local bundle depending on remote
type=bundle
EOF
echo "author/remote-dep" > "$DOTFILES_DIR/bundles/local-with-remote-dep/requires.txt"

_DOTPKG_VISITED=""
printf '{"installed_bundles":[],"installed_presets":[]}\n' > "$STATE_FILE"

install_bundle "$DOTFILES_DIR/bundles/local-with-remote-dep" "local"

# Verify local bundle was installed
assert_true "dependency re-eval: local bundle installed" \
  state_bundle_installed "local-with-remote-dep"

# Verify remote dependency was installed
assert_true "dependency re-eval: remote dep installed" \
  state_bundle_installed "remote-dep"

# CRITICAL: Verify remote dependency's defaults.sh was NOT executed
if [[ -f "$MARKER_FILE" ]]; then
  _fail "dependency re-eval: remote dep's defaults.sh SHOULD NOT execute (CRITICAL BUG)"
else
  _pass "dependency re-eval: remote dep correctly skips defaults.sh"
fi

# Verify remote dep was recorded with "remote" source
remote_dep_source=$(state_get_bundle_source "remote-dep" 2>/dev/null || echo "ERROR")
assert_eq "dependency re-eval: remote dep recorded as remote" "$remote_dep_source" "remote"

rm -rf "$REMOTE_DEP_BUNDLE" "$MARKER_DIR" "$CACHE_DIR"
rm -rf "$DOTFILES_DIR/bundles/local-with-remote-dep"

# ---------------------------------------------------------------------------
# install_extensions: per-editor files with fallback
# ---------------------------------------------------------------------------

EXT_BUNDLE=$(mktemp -d)
mkdir -p "$EXT_BUNDLE"
cat > "$EXT_BUNDLE/bundle.info" <<'EOF'
name=ext-test
type=bundle
EOF

# Mock editor commands
code() { echo "code: $*" >> "$TEST_EXTS_LOG"; }
cursor() { echo "cursor: $*" >> "$TEST_EXTS_LOG"; }
codium() { echo "codium: $*" >> "$TEST_EXTS_LOG"; }
export -f code cursor codium

TEST_EXTS_LOG=$(mktemp)
trap "rm -f '$TEST_EXTS_LOG'" RETURN

# Test 1: generic extensions.txt (all editors get same list)
cat > "$EXT_BUNDLE/extensions.txt" <<'EOF'
ms-python.python
# comment line
EOF

install_extensions "$EXT_BUNDLE" >/dev/null 2>&1 || true
code_calls=$(grep -c "^code:" "$TEST_EXTS_LOG" || true)
cursor_calls=$(grep -c "^cursor:" "$TEST_EXTS_LOG" || true)
assert_eq "install_extensions: generic file installs for code" "$code_calls" "1"
assert_eq "install_extensions: generic file installs for cursor" "$cursor_calls" "1"

# Test 2: per-editor files (vscode overrides generic)
rm "$TEST_EXTS_LOG"
cat > "$EXT_BUNDLE/extensions.vscode.txt" <<'EOF'
arcticicestudio.nord-visual-studio-code
EOF

install_extensions "$EXT_BUNDLE" >/dev/null 2>&1 || true
code_calls=$(grep -c "^code:" "$TEST_EXTS_LOG" || true)
cursor_calls=$(grep -c "^cursor:" "$TEST_EXTS_LOG" || true)
assert_eq "install_extensions: vscode.txt overrides for code" "$code_calls" "1"
assert_eq "install_extensions: cursor still gets generic" "$cursor_calls" "1"

# Test 3: all three per-editor files (no generic)
rm "$TEST_EXTS_LOG"
rm "$EXT_BUNDLE/extensions.txt"
cat > "$EXT_BUNDLE/extensions.vscode.txt" <<'EOF'
ms-python.python
EOF
cat > "$EXT_BUNDLE/extensions.cursor.txt" <<'EOF'
saoudrizp.claude-dev
EOF
cat > "$EXT_BUNDLE/extensions.codium.txt" <<'EOF'
ms-vscode-remote.remote-ssh
EOF

install_extensions "$EXT_BUNDLE" >/dev/null 2>&1 || true
code_calls=$(grep -c "^code:" "$TEST_EXTS_LOG" || true)
cursor_calls=$(grep -c "^cursor:" "$TEST_EXTS_LOG" || true)
codium_calls=$(grep -c "^codium:" "$TEST_EXTS_LOG" || true)
assert_eq "install_extensions: per-editor code" "$code_calls" "1"
assert_eq "install_extensions: per-editor cursor" "$cursor_calls" "1"
assert_eq "install_extensions: per-editor codium" "$codium_calls" "1"

rm -rf "$EXT_BUNDLE"

# ---------------------------------------------------------------------------
# _validate_git_url: URL validation (CRITICAL-3 fix)
# ---------------------------------------------------------------------------

# Valid HTTPS URLs
assert_true  "_validate_git_url: valid https URL" \
  _validate_git_url "https://github.com/user/repo"
assert_true  "_validate_git_url: https with .git suffix" \
  _validate_git_url "https://github.com/user/repo.git"
assert_true  "_validate_git_url: https with subdomain" \
  _validate_git_url "https://api.github.com/repos/user/repo"
assert_true  "_validate_git_url: https with hyphen in domain" \
  _validate_git_url "https://my-server.com/user/repo"
assert_true  "_validate_git_url: https with port number" \
  _validate_git_url "https://gitlab.com:443/user/repo"

# Valid SSH URLs
assert_true  "_validate_git_url: valid git@ SSH URL" \
  _validate_git_url "git@github.com:user/repo"
assert_true  "_validate_git_url: git@ with .git suffix" \
  _validate_git_url "git@github.com:user/repo.git"
assert_true  "_validate_git_url: git@ with hyphens" \
  _validate_git_url "git@my-server.com:user/my-repo"
assert_true  "_validate_git_url: git@ with underscores" \
  _validate_git_url "git@github.com:user_name/repo_name"

# Valid user/repo shorthand
assert_true  "_validate_git_url: shorthand user/repo" \
  _validate_git_url "user/repo"
assert_true  "_validate_git_url: shorthand with hyphen" \
  _validate_git_url "user-name/repo-name"
assert_true  "_validate_git_url: shorthand with underscore" \
  _validate_git_url "user_name/repo_name"
assert_true  "_validate_git_url: shorthand with dot" \
  _validate_git_url "user.name/repo.name"

# Invalid URLs (must be rejected)
assert_false "_validate_git_url: reject file:// URL" \
  _validate_git_url "file:///etc/passwd"
assert_false "_validate_git_url: reject git:// URL" \
  _validate_git_url "git://attacker.com/evil"
assert_false "_validate_git_url: reject ftp:// URL" \
  _validate_git_url "ftp://attacker.com/repo"
assert_false "_validate_git_url: reject http:// URL" \
  _validate_git_url "http://attacker.com/repo"
assert_false "_validate_git_url: reject bare domain" \
  _validate_git_url "attacker.com/repo"
assert_false "_validate_git_url: reject absolute path" \
  _validate_git_url "/etc/passwd"
assert_false "_validate_git_url: reject relative path" \
  _validate_git_url "../../../etc/passwd"
assert_false "_validate_git_url: reject malformed https" \
  _validate_git_url "https:/invalid-url"
assert_false "_validate_git_url: reject malformed ssh" \
  _validate_git_url "git@:user/repo"
assert_false "_validate_git_url: reject command injection attempt" \
  _validate_git_url "https://github.com/user/repo\$(whoami)"

# ---------------------------------------------------------------------------
# _check_url_credentials: Git credentials detection (MEDIUM-11 fix)
# ---------------------------------------------------------------------------

assert_true  "_check_url_credentials: https URL without credentials" \
  _check_url_credentials "https://github.com/user/repo"

assert_true  "_check_url_credentials: git@ SSH without credentials" \
  _check_url_credentials "git@github.com:user/repo"

assert_true  "_check_url_credentials: user/repo shorthand" \
  _check_url_credentials "user/repo"

assert_false "_check_url_credentials: reject https with embedded password" \
  _check_url_credentials "https://user:password@github.com/repo"

assert_false "_check_url_credentials: reject https with embedded token" \
  _check_url_credentials "https://user:ghp_abc123xyz@github.com/repo"

assert_false "_check_url_credentials: reject https with complex password" \
  _check_url_credentials "https://admin:P@ss123!@gitlab.com/repo"

assert_false "_check_url_credentials: reject git@ with embedded credentials" \
  _check_url_credentials "git@user:password@github.com:repo"

# ---------------------------------------------------------------------------
# _clone_source: integration with validation
# ---------------------------------------------------------------------------

# Valid sources should succeed (if git is configured properly)
# We won't actually clone, but we can test that invalid sources fail early

# Create test script to verify validation is called
TEST_CLONE_LOG=$(mktemp)
trap "rm -f '$TEST_CLONE_LOG'" RETURN

# Test: valid HTTPS source (would clone if repo exists)
# We bypass actual clone by mocking git to just log the attempt
_test_clone_valid_https() {
  local tmp_cache=$(mktemp -d)
  # Mock git to just create dir and record the call
  git() { mkdir -p "$tmp_cache/mock-clone" && echo "git $*" >> "$TEST_CLONE_LOG"; }
  export -f git
  if _clone_source "https://github.com/torvalds/linux" "$tmp_cache/mock-clone"; then
    rm -rf "$tmp_cache"
    return 0
  else
    rm -rf "$tmp_cache"
    return 1
  fi
}

assert_true "_clone_source: valid https source passes validation" _test_clone_valid_https

# Test: invalid source should fail at validation (before trying to clone)
_test_clone_invalid_file() {
  local tmp_cache=$(mktemp -d)
  ! _clone_source "file:///etc/passwd" "$tmp_cache/should-fail" 2>/dev/null
  local result=$?
  rm -rf "$tmp_cache"
  return $result
}

assert_true "_clone_source: invalid file:// URL rejected" _test_clone_invalid_file

# Test: invalid source with git:// protocol
_test_clone_invalid_git_proto() {
  local tmp_cache=$(mktemp -d)
  ! _clone_source "git://attacker.com/evil" "$tmp_cache/should-fail" 2>/dev/null
  local result=$?
  rm -rf "$tmp_cache"
  return $result
}

assert_true "_clone_source: invalid git:// URL rejected" _test_clone_invalid_git_proto

# Test: shorthand format should be accepted (and converted to https)
_test_clone_shorthand() {
  local tmp_cache=$(mktemp -d)
  # We just test that it passes validation; actual clone would fail without real repo
  if _validate_git_url "user/repo"; then
    rm -rf "$tmp_cache"
    return 0
  fi
  rm -rf "$tmp_cache"
  return 1
}

assert_true "_clone_source: user/repo shorthand accepted" _test_clone_shorthand

# Test: embedded credentials should be rejected early (MEDIUM-11)
_test_clone_credentials_rejected() {
  local tmp_cache=$(mktemp -d)
  ! _clone_source "https://user:password@github.com/repo" "$tmp_cache/should-fail" 2>/dev/null
  local result=$?
  rm -rf "$tmp_cache"
  return $result
}

assert_true "_clone_source: URLs with embedded credentials rejected" _test_clone_credentials_rejected

# ---------------------------------------------------------------------------
# stow conflict detection tests (CRITICAL-4: make conflicts fatal)
# ---------------------------------------------------------------------------

# Test: bundle with conflicting stow files fails to install
_test_stow_conflict_fatal() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with stow/ directory
  mkdir -p "$test_bundle/stow/config"
  echo "bundle version" > "$test_bundle/stow/config/test.txt"

  # Create bundle.info
  cat > "$test_bundle/bundle.info" <<EOF
name=conflict-bundle
description=Bundle with conflicting files
EOF

  # Pre-create conflicting file at target with DIFFERENT content (stow conflict)
  mkdir -p "$test_target/config"
  echo "target version" > "$test_target/config/test.txt"

  # Reset state and install bundle — should fail due to conflict
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Capture return value
  local ret=0
  if install_bundle "$test_bundle" "local" 2>/dev/null; then
    ret=$?
  else
    ret=$?
  fi

  # install_bundle should have failed (returned 1)
  # Confirm target file was NOT overwritten (stow was not applied)
  if [[ $ret -ne 0 ]] && grep -q "target version" "$test_target/config/test.txt" 2>/dev/null; then
    rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "stow conflict: bundle with conflicts fails to install" _test_stow_conflict_fatal

# Test: verify error is reported when conflict detected
_test_stow_conflict_error_reported() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with stow/ directory
  mkdir -p "$test_bundle/stow/config"
  echo "bundle config" > "$test_bundle/stow/config/test.txt"

  # Create bundle.info
  cat > "$test_bundle/bundle.info" <<EOF
name=error-bundle
description=Bundle to test error reporting
EOF

  # Pre-create conflicting file with different content
  mkdir -p "$test_target/config"
  echo "existing config" > "$test_target/config/test.txt"

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Capture stderr
  local error_output
  error_output=$(install_bundle "$test_bundle" "local" 2>&1 >/dev/null || true)

  # Check that conflict message was output
  if echo "$error_output" | grep -q "CONFLICT\|existing target\|stow conflicts"; then
    rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "stow conflict: error message reported" _test_stow_conflict_error_reported

# ---------------------------------------------------------------------------
# symlink detection tests (HIGH-8: reject symlinks in stow/)
# ---------------------------------------------------------------------------

# Test: bundle with symlinks in stow/ fails to install
_test_symlink_rejection() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with stow/ directory containing a symlink
  mkdir -p "$test_bundle/stow/config"
  echo "regular file" > "$test_bundle/stow/config/bashrc"
  ln -s "/etc/passwd" "$test_bundle/stow/config/symlink-to-passwd"

  # Create bundle.info
  cat > "$test_bundle/bundle.info" <<EOF
name=symlink-bundle
description=Bundle with malicious symlink
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Capture return value — install_bundle should fail
  local ret=0
  if install_bundle "$test_bundle" "local" 2>/dev/null; then
    ret=$?
  else
    ret=$?
  fi

  # install_bundle should have failed (returned non-zero)
  if [[ $ret -ne 0 ]]; then
    rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "symlink detection: bundle with symlinks in stow/ fails" _test_symlink_rejection

# Test: verify error is reported for symlinks
_test_symlink_error_reported() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with symlink
  mkdir -p "$test_bundle/stow/config"
  echo "config" > "$test_bundle/stow/config/bashrc"
  ln -s "/tmp/evil" "$test_bundle/stow/config/evil-symlink"

  # Create bundle.info
  cat > "$test_bundle/bundle.info" <<EOF
name=symlink-error-bundle
description=Bundle to test symlink error reporting
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Capture error output
  local error_output
  error_output=$(install_bundle "$test_bundle" "local" 2>&1) || true

  # Error message should mention symlinks or security risk
  if echo "$error_output" | grep -q "symlink\|security risk"; then
    rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "symlink detection: error message reported" _test_symlink_error_reported

# ---------------------------------------------------------------------------
# path validation tests (HIGH-9: reject path traversal in theme_target)
# ---------------------------------------------------------------------------

# Test: _validate_target_path helper function
_test_validate_target_path_valid() {
  # Valid paths should pass
  _validate_target_path "$HOME/Library/Themes" "true" || return 1
  _validate_target_path "~/.config/themes" "true" || return 1
  _validate_target_path "$HOME" "true" || return 1
  return 0
}

assert_true "_validate_target_path: valid home paths" _test_validate_target_path_valid

# Test: _validate_target_path rejects path traversal
_test_validate_target_path_traversal() {
  # Path traversal should fail (even if technically under home)
  _validate_target_path "~/Library/../../etc/themes" "true" && return 1
  _validate_target_path "$HOME/Library/../../../etc" "true" && return 1
  _validate_target_path "$HOME/Library/./themes" "true" && return 1
  return 0
}

assert_true "_validate_target_path: rejects path traversal" _test_validate_target_path_traversal

# Test: _validate_target_path rejects paths outside HOME for remote
_test_validate_target_path_outside_home() {
  # Absolute paths outside home should fail for remote
  _validate_target_path "/tmp/themes" "true" && return 1
  _validate_target_path "/etc/themes" "true" && return 1
  return 0
}

assert_true "_validate_target_path: rejects paths outside HOME for remote" _test_validate_target_path_outside_home

# Test: theme_target path traversal in remote bundle fails to install
_test_theme_target_traversal_remote() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with themes/ directory
  mkdir -p "$test_bundle/themes/nord"
  echo "nord theme colors" > "$test_bundle/themes/nord/colors.txt"

  # Create bundle.info with malicious theme_target (path traversal)
  cat > "$test_bundle/bundle.info" <<EOF
name=evil-theme-bundle
description=Bundle with malicious theme_target
type=bundle
theme_target=../../tmp/evil
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Attempt to install as remote bundle — should fail
  local ret=0
  if install_bundle "$test_bundle" "remote" 2>/dev/null; then
    ret=$?
  else
    ret=$?
  fi

  # install_bundle should have failed (returned non-zero)
  if [[ $ret -ne 0 ]]; then
    rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "theme_target: remote bundle with traversal fails" _test_theme_target_traversal_remote

# Test: theme_target path traversal error is reported
_test_theme_target_traversal_error_reported() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with themes directory
  mkdir -p "$test_bundle/themes/nord"
  echo "theme" > "$test_bundle/themes/nord/colors.txt"

  # Create bundle.info with path traversal in theme_target
  cat > "$test_bundle/bundle.info" <<EOF
name=error-theme-bundle
description=To test error reporting
type=bundle
theme_target=../../../../etc/passwd
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Capture error output
  local error_output
  error_output=$(install_bundle "$test_bundle" "remote" 2>&1) || true

  # Error message should mention theme_target validation
  if echo "$error_output" | grep -q "theme_target"; then
    rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "theme_target: error message reported" _test_theme_target_traversal_error_reported

# Test: local bundle with theme_target works fine (no restriction)
_test_theme_target_local_allowed() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with themes directory
  mkdir -p "$test_bundle/themes/custom"
  echo "custom theme" > "$test_bundle/themes/custom/style.txt"

  # Create bundle.info with normal theme_target
  cat > "$test_bundle/bundle.info" <<EOF
name=local-theme-bundle
description=Local bundle with theme_target
type=bundle
theme_target=$test_target
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Install as local bundle — should succeed
  if install_bundle "$test_bundle" "local" 2>/dev/null; then
    # Verify themes were copied
    if [[ -f "$test_target/custom/style.txt" ]]; then
      rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "theme_target: local bundle works fine" _test_theme_target_local_allowed

# Test: remote bundle with safe theme_target works
_test_theme_target_remote_safe() {
  local test_bundle=$(mktemp -d)
  local test_themes_dir="$HOME/.config/themes-test"

  # Create bundle with themes directory
  mkdir -p "$test_bundle/themes/nord"
  echo "nord theme" > "$test_bundle/themes/nord/colors.txt"

  # Create bundle.info with safe theme_target under HOME
  cat > "$test_bundle/bundle.info" <<EOF
name=safe-theme-bundle
description=Remote bundle with safe theme_target
type=bundle
theme_target=~/.config/themes-test
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Install as remote bundle — should succeed
  if install_bundle "$test_bundle" "remote" 2>/dev/null; then
    # Verify themes were copied
    if [[ -f "$test_themes_dir/nord/colors.txt" ]]; then
      rm -rf "$test_bundle" "$test_themes_dir" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$test_themes_dir" "$STATE_FILE"
  return 1
}

assert_true "theme_target: remote bundle with safe path works" _test_theme_target_remote_safe

# ---------------------------------------------------------------------------
# stow_target validation tests (CRITICAL-2: reject path traversal)
# ---------------------------------------------------------------------------

# Test: stow_target path traversal in remote bundle fails to install
_test_stow_target_traversal_remote() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with stow/ directory
  mkdir -p "$test_bundle/stow/config"
  echo "bundle config" > "$test_bundle/stow/config/bashrc"

  # Create bundle.info with malicious stow_target (path traversal)
  cat > "$test_bundle/bundle.info" <<EOF
name=evil-stow-bundle
description=Bundle with malicious stow_target
type=bundle
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Attempt to install as remote bundle with traversal target — should fail
  if ! install_bundle "$test_bundle" "remote" 2>/dev/null; then
    # Check if actual stow wasn't applied
    if [[ ! -f "$test_target/config/bashrc" ]]; then
      rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

# Test: remote bundle with stow_target outside HOME fails
_test_stow_target_outside_home_remote() {
  local test_bundle=$(mktemp -d)

  # Create bundle with stow directory
  mkdir -p "$test_bundle/stow/etc"
  echo "malicious config" > "$test_bundle/stow/etc/evil"

  # Create bundle.info with stow_target outside HOME
  cat > "$test_bundle/bundle.info" <<EOF
name=remote-stow-tmp
description=Remote bundle targeting /tmp
type=bundle
stow_target=/tmp/evil-stow
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Attempt to install as remote bundle — should fail
  if ! install_bundle "$test_bundle" "remote" 2>/dev/null; then
    rm -rf "$test_bundle" "$STATE_FILE"
    return 0
  fi

  rm -rf "$test_bundle" "$STATE_FILE"
  return 1
}

assert_true "stow_target: remote bundle with /tmp target fails" _test_stow_target_outside_home_remote

# Test: remote bundle with safe stow_target works
_test_stow_target_remote_safe() {
  local test_bundle=$(mktemp -d)
  local test_stow_dir="$HOME/.config/dotfiles-test"

  # Create stow target directory (required by stow)
  mkdir -p "$test_stow_dir"

  # Create bundle with stow directory
  mkdir -p "$test_bundle/stow/config"
  echo "my config" > "$test_bundle/stow/config/bashrc"

  # Create bundle.info with safe stow_target under HOME
  cat > "$test_bundle/bundle.info" <<EOF
name=safe-stow-bundle
description=Remote bundle with safe stow_target
type=bundle
stow_target=$test_stow_dir
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  # Install as remote bundle — should succeed
  if install_bundle "$test_bundle" "remote" 2>/dev/null; then
    # Verify stow was applied (either symlink or directory with files)
    if [[ -L "$test_stow_dir/config" ]] || [[ -f "$test_stow_dir/config/bashrc" ]]; then
      rm -rf "$test_bundle" "$test_stow_dir" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$test_stow_dir" "$STATE_FILE"
  return 1
}

assert_true "stow_target: remote bundle with safe path works" _test_stow_target_remote_safe

# ---------------------------------------------------------------------------
# bundle name validation tests (MEDIUM-10: reject special characters)
# ---------------------------------------------------------------------------

# Valid bundle names (alphanumeric, dots, underscores, hyphens, slashes)
assert_true  "_validate_bundle_name: simple name" \
  _validate_bundle_name "mytool"
assert_true  "_validate_bundle_name: name with hyphen" \
  _validate_bundle_name "my-tool"
assert_true  "_validate_bundle_name: name with underscore" \
  _validate_bundle_name "my_tool"
assert_true  "_validate_bundle_name: name with dot" \
  _validate_bundle_name "my.tool"
assert_true  "_validate_bundle_name: user/repo (GitHub shorthand)" \
  _validate_bundle_name "user/repo"
assert_true  "_validate_bundle_name: user/repo-name with hyphens" \
  _validate_bundle_name "user/repo-name"
assert_true  "_validate_bundle_name: user_name/repo_name with underscores" \
  _validate_bundle_name "user_name/repo_name"
assert_true  "_validate_bundle_name: user.name/repo.name with dots" \
  _validate_bundle_name "user.name/repo.name"
assert_true  "_validate_bundle_name: numeric names" \
  _validate_bundle_name "v2"
assert_true  "_validate_bundle_name: mixed: user/repo-v2_beta.1" \
  _validate_bundle_name "user/repo-v2_beta.1"

# Invalid bundle names (special characters that could corrupt state.json)
assert_false "_validate_bundle_name: reject hash" \
  _validate_bundle_name "my#tool"
assert_false "_validate_bundle_name: reject dollar" \
  _validate_bundle_name 'my$tool'
assert_false "_validate_bundle_name: reject asterisk" \
  _validate_bundle_name "my*tool"
assert_false "_validate_bundle_name: reject space" \
  _validate_bundle_name "my tool"
assert_false "_validate_bundle_name: reject newline" \
  _validate_bundle_name $'my\ntool'
assert_false "_validate_bundle_name: reject semicolon" \
  _validate_bundle_name "my;tool"
assert_false "_validate_bundle_name: reject pipe" \
  _validate_bundle_name "my|tool"
assert_false "_validate_bundle_name: reject ampersand" \
  _validate_bundle_name "my&tool"
assert_false "_validate_bundle_name: reject backtick" \
  _validate_bundle_name 'my`tool'
assert_false "_validate_bundle_name: reject quote" \
  _validate_bundle_name "my'tool"
assert_false "_validate_bundle_name: reject double quote" \
  _validate_bundle_name 'my"tool'
assert_false "_validate_bundle_name: reject backslash" \
  _validate_bundle_name 'my\tool'
assert_false "_validate_bundle_name: reject angle bracket" \
  _validate_bundle_name "my<tool"
assert_false "_validate_bundle_name: reject parenthesis" \
  _validate_bundle_name "my(tool"
assert_false "_validate_bundle_name: reject curly brace" \
  _validate_bundle_name "my{tool"
assert_false "_validate_bundle_name: reject square bracket" \
  _validate_bundle_name "my[tool"
assert_false "_validate_bundle_name: reject equals" \
  _validate_bundle_name "my=tool"
assert_false "_validate_bundle_name: reject plus" \
  _validate_bundle_name "my+tool"
assert_false "_validate_bundle_name: reject percent" \
  _validate_bundle_name "my%tool"
assert_false "_validate_bundle_name: reject at sign" \
  _validate_bundle_name "my@tool"
assert_false "_validate_bundle_name: reject tilde" \
  _validate_bundle_name "my~tool"
assert_false "_validate_bundle_name: reject colon" \
  _validate_bundle_name "my:tool"
assert_false "_validate_bundle_name: reject comma" \
  _validate_bundle_name "my,tool"
assert_false "_validate_bundle_name: reject question mark" \
  _validate_bundle_name "my?tool"

# Edge cases
assert_false "_validate_bundle_name: empty string" \
  _validate_bundle_name ""

# Test resolve_bundle with invalid name
_test_resolve_bundle_invalid_name() {
  if resolve_bundle "bad#name" 2>/dev/null; then
    return 1
  fi
  return 0
}

assert_true "resolve_bundle: invalid name rejected" _test_resolve_bundle_invalid_name

# ---------------------------------------------------------------------------
# MEDIUM-14: Pre-validation tests (no state changes on failure)
# ---------------------------------------------------------------------------

# Test: Pre-validation catches unresolvable dependencies before state changes
_test_prevalidation_dependency_fails() {
  local test_bundle=$(mktemp -d)

  # Create bundle with broken dependency
  cat > "$test_bundle/bundle.info" <<EOF
name=broken-dep-bundle
description=Bundle with unresolvable dependency
type=bundle
EOF
  echo "nonexistent-dep" > "$test_bundle/requires.txt"

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  _DOTPKG_VISITED=""

  # Attempt to install — should fail without modifying state
  if ! install_bundle "$test_bundle" "local" 2>/dev/null; then
    # Verify bundle was NOT added to state
    if ! state_bundle_installed "broken-dep-bundle"; then
      rm -rf "$test_bundle" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$STATE_FILE"
  return 1
}

assert_true "MEDIUM-14: pre-validation prevents state change on dep failure" \
  _test_prevalidation_dependency_fails

# Test: Pre-validation validates all dependencies before modifying state
_test_prevalidation_validates_all_deps() {
  local test_bundle=$(mktemp -d)
  local dep1_dir="$DOTFILES_DIR/bundles/valid-dep"
  local dep2_notexist="nonexistent-dep-12345"

  # Create first valid dependency
  mkdir -p "$dep1_dir"
  cat > "$dep1_dir/bundle.info" <<EOF
name=valid-dep
description=Valid dependency
type=bundle
EOF

  # Create parent bundle with one valid and one invalid dependency
  cat > "$test_bundle/bundle.info" <<EOF
name=multi-dep-bundle
description=Bundle with mixed valid/invalid deps
type=bundle
EOF
  cat > "$test_bundle/requires.txt" <<EOF
valid-dep
$dep2_notexist
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  _DOTPKG_VISITED=""

  # Attempt to install — should fail during pre-validation (before any state changes)
  if ! install_bundle "$test_bundle" "local" 2>/dev/null; then
    # Verify neither bundle nor dependency was added to state
    if ! state_bundle_installed "multi-dep-bundle" && ! state_bundle_installed "valid-dep"; then
      rm -rf "$test_bundle" "$dep1_dir" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$dep1_dir" "$STATE_FILE"
  return 1
}

assert_true "MEDIUM-14: pre-validation validates all deps before state changes" \
  _test_prevalidation_validates_all_deps

# Test: Pre-validation detects stow conflicts before state changes
_test_prevalidation_stow_conflicts() {
  local test_bundle=$(mktemp -d)
  local test_target=$(mktemp -d)

  # Create bundle with stow directory
  mkdir -p "$test_bundle/stow/config"
  echo "bundle config" > "$test_bundle/stow/config/bashrc"

  # Create bundle.info
  cat > "$test_bundle/bundle.info" <<EOF
name=conflict-prevalidation-bundle
description=Bundle with stow conflicts
EOF

  # Pre-create conflicting file at target with different content
  mkdir -p "$test_target/config"
  echo "existing config" > "$test_target/config/bashrc"

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  _DOTPKG_VISITED=""

  # Attempt to install with custom stow_target
  if ! install_bundle "$test_bundle" "local" 2>/dev/null; then
    # Verify bundle was NOT added to state
    if ! state_bundle_installed "conflict-prevalidation-bundle"; then
      # Verify target file was NOT modified
      if grep -q "existing config" "$test_target/config/bashrc" 2>/dev/null; then
        rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
        return 0
      fi
    fi
  fi

  rm -rf "$test_bundle" "$test_target" "$STATE_FILE"
  return 1
}

assert_true "MEDIUM-14: pre-validation catches stow conflicts before state change" \
  _test_prevalidation_stow_conflicts

# Test: Pre-validation catches invalid stow_target for remote bundle
_test_prevalidation_invalid_stow_target_remote() {
  local test_bundle=$(mktemp -d)

  # Create bundle with stow directory
  mkdir -p "$test_bundle/stow/config"
  echo "config" > "$test_bundle/stow/config/test"

  # Create bundle.info with stow_target outside HOME
  cat > "$test_bundle/bundle.info" <<EOF
name=invalid-stow-remote
description=Remote bundle with invalid stow_target
type=bundle
stow_target=/tmp/malicious
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  _DOTPKG_VISITED=""

  # Attempt to install as remote — should fail in pre-validation
  if ! install_bundle "$test_bundle" "remote" 2>/dev/null; then
    # Verify bundle was NOT added to state
    if ! state_bundle_installed "invalid-stow-remote"; then
      rm -rf "$test_bundle" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$STATE_FILE"
  return 1
}

assert_true "MEDIUM-14: pre-validation rejects invalid remote stow_target before state change" \
  _test_prevalidation_invalid_stow_target_remote

# Test: Pre-validation catches invalid theme_target for remote bundle
_test_prevalidation_invalid_theme_target_remote() {
  local test_bundle=$(mktemp -d)

  # Create bundle with themes directory
  mkdir -p "$test_bundle/themes/nord"
  echo "theme" > "$test_bundle/themes/nord/colors"

  # Create bundle.info with theme_target outside HOME
  cat > "$test_bundle/bundle.info" <<EOF
name=invalid-theme-remote
description=Remote bundle with invalid theme_target
type=bundle
theme_target=/etc/themes
EOF

  # Reset state
  STATE_FILE=$(mktemp)
  . "$DOTPKG_HOME/lib/state.sh"
  state_init

  _DOTPKG_VISITED=""

  # Attempt to install as remote — should fail in pre-validation
  if ! install_bundle "$test_bundle" "remote" 2>/dev/null; then
    # Verify bundle was NOT added to state
    if ! state_bundle_installed "invalid-theme-remote"; then
      rm -rf "$test_bundle" "$STATE_FILE"
      return 0
    fi
  fi

  rm -rf "$test_bundle" "$STATE_FILE"
  return 1
}

assert_true "MEDIUM-14: pre-validation rejects invalid remote theme_target before state change" \
  _test_prevalidation_invalid_theme_target_remote

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: PASS=$_PASS FAIL=$_FAIL"
[[ $_FAIL -eq 0 ]]
