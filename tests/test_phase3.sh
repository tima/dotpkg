#!/usr/bin/env bash
# tests/test_phase3.sh — Phase 3: sources, resolution tiers, create, list, update.
# Sources libs directly (no CLI subprocess) to avoid env propagation issues.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# Isolated temp env
TEST_ROOT=$(mktemp -d)
export DOTPKG_HOME="$TEST_ROOT/.dotpkg"
export STATE_FILE="$DOTPKG_HOME/state.json"
export DOTFILES_DIR="$TEST_ROOT/dotfiles"
# shellcheck disable=SC2064
trap "rm -rf '$TEST_ROOT'" EXIT

mkdir -p "$DOTPKG_HOME/lib" "$DOTFILES_DIR/bundles" "$DOTFILES_DIR/profiles"

# Copy libs into isolated DOTPKG_HOME
cp "$REPO/lib"/*.sh "$DOTPKG_HOME/lib/"

# Source all libs under test
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/state.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/stow.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/helpers.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/bundle.sh"

state_init

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
# _source_cache_key
# ---------------------------------------------------------------------------

assert_eq "cache key: user/repo"         "$(_source_cache_key 'tima/dotpkg-bundles')"             "tima/dotpkg-bundles"
assert_eq "cache key: strip .git"        "$(_source_cache_key 'tima/dotpkg-bundles.git')"         "tima/dotpkg-bundles"
assert_eq "cache key: https URL"         "$(_source_cache_key 'https://github.com/org/repo.git')" "github.com/org/repo"
assert_eq "cache key: git@ URL"          "$(_source_cache_key 'git@github.internal:team/b.git')"  "github.internal/team/b"
assert_eq "cache key: http URL"          "$(_source_cache_key 'http://host.com/a/b.git')"         "host.com/a/b"

# ---------------------------------------------------------------------------
# resolve_bundle — resolution order: local → profiles → sources → github shorthand
# ---------------------------------------------------------------------------

# Local bundle
mkdir -p "$DOTFILES_DIR/bundles/local-tool"
echo "name=local-tool" > "$DOTFILES_DIR/bundles/local-tool/bundle.info"

path=$(resolve_bundle "local-tool")
assert_eq "resolve: local bundle" "$path" "$DOTFILES_DIR/bundles/local-tool"

# Profile
mkdir -p "$DOTFILES_DIR/profiles/myprofile"
cat > "$DOTFILES_DIR/profiles/myprofile/bundle.info" <<'EOF'
name=myprofile
type=profile
EOF

path=$(resolve_bundle "myprofile")
assert_eq "resolve: profile" "$path" "$DOTFILES_DIR/profiles/myprofile"

# Sources — fake a pre-cloned source cache
mkdir -p "$DOTPKG_HOME/cache/sources/tima/dotpkg-bundles/bundles/source-tool"
echo "name=source-tool" > "$DOTPKG_HOME/cache/sources/tima/dotpkg-bundles/bundles/source-tool/bundle.info"
printf 'tima/dotpkg-bundles\n' > "$DOTPKG_HOME/sources"

path=$(resolve_bundle "source-tool")
assert_eq "resolve: source bundle" "$path" "$DOTPKG_HOME/cache/sources/tima/dotpkg-bundles/bundles/source-tool"

# Local wins over source when both exist
mkdir -p "$DOTFILES_DIR/bundles/source-tool"
echo "name=source-tool" > "$DOTFILES_DIR/bundles/source-tool/bundle.info"
path=$(resolve_bundle "source-tool")
assert_eq "resolve: local wins over source" "$path" "$DOTFILES_DIR/bundles/source-tool"
rm -rf "$DOTFILES_DIR/bundles/source-tool"

# GitHub shorthand — fake a pre-cached clone (no network)
mkdir -p "$DOTPKG_HOME/cache/github/someuser/somerepo"
echo "name=somerepo" > "$DOTPKG_HOME/cache/github/someuser/somerepo/bundle.info"

path=$(resolve_bundle "someuser/somerepo")
assert_eq "resolve: github shorthand (cached)" "$path" "$DOTPKG_HOME/cache/github/someuser/somerepo"

# Non-existent bundle → fails
assert_false "resolve: non-existent returns 1" resolve_bundle "doesnotexist"

# Sources checked before GitHub shorthand — put same name in source AND cache/github
mkdir -p "$DOTPKG_HOME/cache/sources/tima/dotpkg-bundles/bundles/ambiguous"
echo "name=ambiguous" > "$DOTPKG_HOME/cache/sources/tima/dotpkg-bundles/bundles/ambiguous/bundle.info"
mkdir -p "$DOTPKG_HOME/cache/github/tima/ambiguous"
echo "name=ambiguous-gh" > "$DOTPKG_HOME/cache/github/tima/ambiguous/bundle.info"

path=$(resolve_bundle "ambiguous")
assert_eq "resolve: sources before github shorthand" "$path" "$DOTPKG_HOME/cache/sources/tima/dotpkg-bundles/bundles/ambiguous"

# ---------------------------------------------------------------------------
# cmd_create — scaffold bundle
# ---------------------------------------------------------------------------

# Source cmd_create from dotpkg script by extracting it
# (simpler: source the main dotpkg and call cmd_create)
# ponytail: eval the function definition from dotpkg rather than running it as a subprocess

# Extract and source cmd_create directly
eval "$(sed -n '/^cmd_create\(\)/,/^}/p' "$REPO/dotpkg")"

cmd_create "mynewbundle"
assert_true  "create: dir exists"   test -d "$DOTFILES_DIR/bundles/mynewbundle"
assert_true  "create: bundle.info"  test -f "$DOTFILES_DIR/bundles/mynewbundle/bundle.info"
assert_true  "create: stow dir"     test -d "$DOTFILES_DIR/bundles/mynewbundle/stow"
assert_eq    "create: name in info" "$(bundle_info_get "$DOTFILES_DIR/bundles/mynewbundle" name)" "mynewbundle"
assert_eq    "create: type in info" "$(bundle_info_get "$DOTFILES_DIR/bundles/mynewbundle" type)" "bundle"

# Duplicate create fails
if cmd_create "mynewbundle" 2>/dev/null; then
  _fail "create: duplicate should fail"
else
  _pass "create: duplicate returns error"
fi

# ---------------------------------------------------------------------------
# install_bundle from source cache
# ---------------------------------------------------------------------------

state_init

SIMPLE_BUNDLE=$(mktemp -d)
cat > "$SIMPLE_BUNDLE/bundle.info" <<'EOF'
name=simple-source
description=From source
type=bundle
EOF

_DOTPKG_VISITED=""
install_bundle "$SIMPLE_BUNDLE" "source:tima/dotpkg-bundles"
assert_true "install: source bundle recorded in state" state_bundle_installed "simple-source"
# Source field stored correctly
src=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
match = [b for b in s['installed_bundles'] if b['name'] == 'simple-source']
print(match[0]['source'] if match else '')
")
assert_eq "install: source field in state" "$src" "source:tima/dotpkg-bundles"

rm -rf "$SIMPLE_BUNDLE"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: PASS=$_PASS FAIL=$_FAIL"
[[ $_FAIL -eq 0 ]]
