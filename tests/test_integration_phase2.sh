#!/usr/bin/env bash
# tests/test_integration_phase2.sh
# Runs dotpkg CLI as a subprocess with an isolated DOTPKG_HOME + DOTFILES_DIR.
# Test bundles are minimal (bundle.info only) — no Brewfile/stow/defaults.sh
# so no system side-effects (brew, stow, defaults write).

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# ---------------------------------------------------------------------------
# Isolated environment
# ---------------------------------------------------------------------------
TEST_ROOT=$(mktemp -d)
DOTPKG_HOME="$TEST_ROOT/.dotpkg"
DOTFILES_DIR="$TEST_ROOT/dotfiles"
STATE_FILE="$DOTPKG_HOME/state.json"
# shellcheck disable=SC2064
trap "rm -rf '$TEST_ROOT'" EXIT

mkdir -p "$DOTPKG_HOME/lib" "$DOTFILES_DIR/bundles" "$DOTFILES_DIR/profiles"
cp "$REPO/dotpkg"    "$DOTPKG_HOME/dotpkg"
cp "$REPO/lib/"*.sh  "$DOTPKG_HOME/lib/"
chmod +x "$DOTPKG_HOME/dotpkg"

# Run dotpkg with isolated DOTPKG_HOME.
# After init writes config, subsequent calls read DOTFILES_DIR from config.
dotpkg_cmd() { DOTPKG_HOME="$DOTPKG_HOME" "$DOTPKG_HOME/dotpkg" "$@"; }

# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
_PASS=0; _FAIL=0
_pass() { echo "PASS: $1"; _PASS=$((_PASS + 1)); }
_fail() { echo "FAIL: $1${2:+ — $2}"; _FAIL=$((_FAIL + 1)); }

assert_true()  { local d="$1"; shift
                 if "$@" 2>/dev/null; then _pass "$d"; else _fail "$d"; fi; }
assert_false() { local d="$1"; shift
                 if ! "$@" 2>/dev/null; then _pass "$d"; else _fail "$d"; fi; }
assert_eq()    { local d="$1" got="$2" want="$3"
                 [[ "$got" == "$want" ]] && { _pass "$d"; return; }
                 _fail "$d" "got='$got' want='$want'"; }

run_ok()  { local d="$1"; shift
            if dotpkg_cmd "$@" >/dev/null 2>&1; then _pass "$d"; else _fail "$d"; fi; }
run_fail(){ local d="$1"; shift
            if ! dotpkg_cmd "$@" >/dev/null 2>&1; then _pass "$d"; else _fail "$d"; fi; }

# ---------------------------------------------------------------------------
# Fixtures: minimal bundles (no Brewfile/stow/defaults.sh → no system side-effects)
# ---------------------------------------------------------------------------

# Root bundle
cat > "$DOTFILES_DIR/bundle.info" <<EOF
name=personal
description=Personal root bundle
author=test
type=bundle
EOF

# devtools bundle (no deps)
mkdir -p "$DOTFILES_DIR/bundles/devtools"
cat > "$DOTFILES_DIR/bundles/devtools/bundle.info" <<EOF
name=devtools
description=Development tools
author=test
type=bundle
EOF

# depA and depB (diamond dependency: profile→depA→depB, profile→depB)
mkdir -p "$DOTFILES_DIR/bundles/depA" "$DOTFILES_DIR/bundles/depB"
cat > "$DOTFILES_DIR/bundles/depA/bundle.info" <<EOF
name=depA
description=Dependency A
type=bundle
EOF
echo "depB" > "$DOTFILES_DIR/bundles/depA/requires.txt"

cat > "$DOTFILES_DIR/bundles/depB/bundle.info" <<EOF
name=depB
description=Dependency B
type=bundle
EOF

# workstation profile: personal + devtools + depA (depA pulls depB)
mkdir -p "$DOTFILES_DIR/profiles/workstation"
cat > "$DOTFILES_DIR/profiles/workstation/bundle.info" <<EOF
name=workstation
description=Workstation profile
author=test
type=profile
EOF
printf 'personal\ndevtools\ndepA\ndepB\n' > "$DOTFILES_DIR/profiles/workstation/requires.txt"

# ---------------------------------------------------------------------------
# TEST: dotpkg init
# ---------------------------------------------------------------------------

run_ok "init: exits 0" init --repo "$DOTFILES_DIR" -y

assert_true "init: state.json created"  test -f "$STATE_FILE"
assert_true "init: config written"      test -f "$DOTPKG_HOME/config"
assert_true "init: config has path"     grep -q "dotfiles_dir=" "$DOTPKG_HOME/config"
assert_true "init: personal in state"   grep -q '"personal"' "$STATE_FILE"
assert_true "init: bundles/ created"    test -d "$DOTFILES_DIR/bundles"

# Config stores correct path
cfg_path=$(grep '^dotfiles_dir=' "$DOTPKG_HOME/config" | cut -d= -f2-)
assert_eq   "init: config path matches" "$cfg_path" "$DOTFILES_DIR"

# ---------------------------------------------------------------------------
# TEST: dotpkg status
# ---------------------------------------------------------------------------

status_out=$(dotpkg_cmd status 2>/dev/null)
assert_true "status: personal in output"  echo "$status_out" | grep -q "personal"
assert_true "status: exits 0"             run_ok "status exits 0" status

json_out=$(dotpkg_cmd status --json 2>/dev/null)
assert_true "status --json: valid JSON"   python3 -c "import json,sys; json.loads(sys.argv[1])" "$json_out"
assert_true "status --json: has bundles"  python3 -c "
import json, sys
s = json.loads(sys.argv[1])
assert 'installed_bundles' in s
assert any(b['name'] == 'personal' for b in s['installed_bundles'])
" "$json_out"

# ---------------------------------------------------------------------------
# TEST: dotpkg add (local bundle)
# ---------------------------------------------------------------------------

run_ok "add: devtools exits 0" add devtools

assert_true "add: devtools in state"  grep -q '"devtools"' "$STATE_FILE"

bundle_count=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
print(len(s['installed_bundles']))
" "$STATE_FILE")
assert_true "add: state has >= 2 bundles" test "$bundle_count" -ge 2

# ---------------------------------------------------------------------------
# TEST: dotpkg add (idempotent — add devtools again, no error)
# ---------------------------------------------------------------------------

run_ok "add: idempotent re-add exits 0" add devtools

count_after=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
print(sum(1 for b in s['installed_bundles'] if b['name'] == 'devtools'))
" "$STATE_FILE")
assert_eq "add: idempotent — devtools recorded once" "$count_after" "1"

# ---------------------------------------------------------------------------
# TEST: dotpkg add (diamond dependency — depA requires depB, profile also lists depB)
# ---------------------------------------------------------------------------

run_ok "add: depA (with depB dependency) exits 0" add depA

assert_true "add: depB installed via dep" grep -q '"depB"' "$STATE_FILE"
depB_count=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
print(sum(1 for b in s['installed_bundles'] if b['name'] == 'depB'))
" "$STATE_FILE")
assert_eq "add: depB recorded exactly once (diamond dedup)" "$depB_count" "1"

# ---------------------------------------------------------------------------
# TEST: dotpkg add (unknown bundle → non-zero exit)
# ---------------------------------------------------------------------------

run_fail "add: unknown bundle exits non-zero" add bundle-does-not-exist

# ---------------------------------------------------------------------------
# TEST: dotpkg list
# ---------------------------------------------------------------------------

list_out=$(dotpkg_cmd list 2>/dev/null)
assert_true "list: devtools in output"    echo "$list_out" | grep -q "devtools"
assert_true "list: workstation in output" echo "$list_out" | grep -q "workstation"

list_local=$(dotpkg_cmd list --local 2>/dev/null)
assert_true "list --local: devtools shown" echo "$list_local" | grep -q "devtools"

# ---------------------------------------------------------------------------
# TEST: dotpkg create
# ---------------------------------------------------------------------------

run_ok "create: exits 0" create newbundle

assert_true "create: dir created"     test -d "$DOTFILES_DIR/bundles/newbundle"
assert_true "create: bundle.info"     test -f "$DOTFILES_DIR/bundles/newbundle/bundle.info"
assert_true "create: stow dir"        test -d "$DOTFILES_DIR/bundles/newbundle/stow"
assert_true "create: name field"      grep -q "name=newbundle" "$DOTFILES_DIR/bundles/newbundle/bundle.info"

run_fail "create: duplicate exits non-zero" create newbundle

# ---------------------------------------------------------------------------
# TEST: dotpkg init with profile
# ---------------------------------------------------------------------------

# Fresh state for profile test
rm -f "$STATE_FILE"

run_ok "init --profile: exits 0" init --repo "$DOTFILES_DIR" --profile workstation -y

assert_true "init --profile: personal installed"    grep -q '"personal"'    "$STATE_FILE"
assert_true "init --profile: devtools installed"    grep -q '"devtools"'    "$STATE_FILE"
assert_true "init --profile: workstation installed" grep -q '"workstation"' "$STATE_FILE"
assert_true "init --profile: depA installed"        grep -q '"depA"'        "$STATE_FILE"
assert_true "init --profile: depB installed once"   python3 -c "
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
n = sum(1 for b in s['installed_bundles'] if b['name'] == 'depB')
sys.exit(0 if n == 1 else 1)
" "$STATE_FILE"

# ---------------------------------------------------------------------------
# TEST: dotpkg sync (idempotent)
# ---------------------------------------------------------------------------

bundle_count_before=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
print(len(s['installed_bundles']))
" "$STATE_FILE")

run_ok "sync: exits 0" sync

bundle_count_after=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: s = json.load(f)
print(len(s['installed_bundles']))
" "$STATE_FILE")

assert_eq "sync: idempotent (bundle count unchanged)" "$bundle_count_after" "$bundle_count_before"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: PASS=$_PASS FAIL=$_FAIL"
[[ $_FAIL -eq 0 ]]
