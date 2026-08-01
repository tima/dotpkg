#!/usr/bin/env bash
# tests/test_helpers.sh — Phase 4: preset signatures, hotkeys, local overrides, state tracking, gum fallback.
# Mocks: defaults, killall, osascript, sqlite3, open, PlistBuddy, gum so no system side-effects.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

TEST_ROOT=$(mktemp -d)
export DOTPKG_HOME="$TEST_ROOT/.dotpkg"
export STATE_FILE="$DOTPKG_HOME/state.json"
export DOTFILES_DIR="$TEST_ROOT/dotfiles"
# shellcheck disable=SC2064
trap "rm -rf '$TEST_ROOT'" EXIT

mkdir -p "$DOTPKG_HOME/lib" "$DOTPKG_HOME/presets" "$DOTFILES_DIR"

DEFAULTS_LOG="$TEST_ROOT/defaults.log"
KILLALL_LOG="$TEST_ROOT/killall.log"

# ---------------------------------------------------------------------------
# Mock system commands (bash functions shadow PATH executables when sourced)
# ---------------------------------------------------------------------------
defaults()   { echo "defaults $*" >> "$DEFAULTS_LOG"; }
killall()    { echo "killall $*" >> "$KILLALL_LOG"; }
osascript()  { :; }
sqlite3()    { :; }
open()       { :; }
PlistBuddy() { :; }
export -f defaults killall osascript sqlite3 open

# Source libs
cp "$REPO/lib"/*.sh "$DOTPKG_HOME/lib/"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/state.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/prompt.sh"
# shellcheck disable=SC1090
. "$DOTPKG_HOME/lib/helpers.sh"

state_init

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

defaults_called_with() {
  grep -qF "$*" "$DEFAULTS_LOG" 2>/dev/null
}

reset_logs() { : > "$DEFAULTS_LOG"; : > "$KILLALL_LOG"; }

# ---------------------------------------------------------------------------
# dotpkg_preset — unknown category
# ---------------------------------------------------------------------------
assert_false "preset: unknown category returns 1" dotpkg_preset unknown-category

# ---------------------------------------------------------------------------
# keyboard preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset keyboard
assert_true  "keyboard: KeyRepeat written"         defaults_called_with "NSGlobalDomain KeyRepeat -int 2"
assert_true  "keyboard: InitialKeyRepeat written"  defaults_called_with "NSGlobalDomain InitialKeyRepeat -int 15"
assert_true  "keyboard: auto-capitalize disabled"  defaults_called_with "NSAutomaticCapitalizationEnabled -bool false"

reset_logs
dotpkg_preset keyboard --key-repeat 4 --initial-key-repeat 20
assert_true  "keyboard: --key-repeat flag honored"         defaults_called_with "KeyRepeat -int 4"
assert_true  "keyboard: --initial-key-repeat flag honored" defaults_called_with "InitialKeyRepeat -int 20"

assert_false "keyboard: unknown flag returns 1" dotpkg_preset keyboard --bad-flag foo

# ---------------------------------------------------------------------------
# finder preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset finder
assert_true "finder: show all files"              defaults_called_with "AppleShowAllFiles -bool true"
assert_true "finder: posix path in title"         defaults_called_with "_FXShowPosixPathInTitle -bool true"
assert_true "finder: expand save dialog"          defaults_called_with "NSNavPanelExpandedStateForSaveMode -bool true"
assert_true "finder: expand print dialog"         defaults_called_with "PMPrintingExpandedStateForPrint2 -bool true"
assert_true "finder: no DS_Store on network"      defaults_called_with "DSDontWriteNetworkStores -bool true"
assert_true "finder: no DS_Store on USB"          defaults_called_with "DSDontWriteUSBStores -bool true"

# ---------------------------------------------------------------------------
# dock preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset dock
assert_true "dock: tilesize default 48"   defaults_called_with "tilesize -int 48"
assert_true "dock: autohide default off"  defaults_called_with "autohide -bool false"

reset_logs
dotpkg_preset dock --icon-size 36 --auto-hide true
assert_true "dock: --icon-size flag honored"   defaults_called_with "tilesize -int 36"
assert_true "dock: --auto-hide flag honored"   defaults_called_with "autohide -bool true"

assert_false "dock: unknown flag returns 1" dotpkg_preset dock --bad-flag x

# ---------------------------------------------------------------------------
# trackpad preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset trackpad
assert_true "trackpad: force click disabled" defaults_called_with "ForceSuppressed -bool true"

reset_logs
dotpkg_preset trackpad --enable-tap-to-click
assert_true "trackpad: tap-to-click enabled" defaults_called_with "Clicking -bool true"

reset_logs
dotpkg_preset trackpad --enable-force-click
assert_true "trackpad: force click enabled"  defaults_called_with "ForceSuppressed -bool false"

# ---------------------------------------------------------------------------
# screenshots preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset screenshots
assert_true "screenshots: default location written" defaults_called_with "location -string"

reset_logs
dotpkg_preset screenshots --location /tmp/shots
assert_true "screenshots: --location flag honored" defaults_called_with "/tmp/shots"

# ---------------------------------------------------------------------------
# display preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset display
assert_true "display: idleTime written"           defaults_called_with "idleTime 300"
assert_true "display: askForPassword written"     defaults_called_with "askForPassword -int 1"

reset_logs
dotpkg_preset display --screensaver-idle 600
assert_true "display: --screensaver-idle flag honored" defaults_called_with "idleTime 600"

# ---------------------------------------------------------------------------
# menubar preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset menubar
assert_true "menubar: BatteryShowPercentage written" defaults_called_with "BatteryShowPercentage -bool true"
assert_true "menubar: Siri hidden"                   defaults_called_with "StatusMenuVisible -bool false"

reset_logs
dotpkg_preset menubar --show-battery-percentage false
assert_true "menubar: --show-battery-percentage flag honored" defaults_called_with "BatteryShowPercentage -bool false"

# ---------------------------------------------------------------------------
# accent-color preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset accent-color
assert_true "accent-color: default graphite (-1)" defaults_called_with "AppleAccentColor -int -1"

reset_logs
dotpkg_preset accent-color --value blue
assert_true "accent-color: --value blue (4)"      defaults_called_with "AppleAccentColor -int 4"

assert_false "accent-color: unknown color returns 1" dotpkg_preset accent-color --value ultraviolet

# ---------------------------------------------------------------------------
# spotlight preset
# ---------------------------------------------------------------------------
dotpkg_preset spotlight
_pass "spotlight: exits 0 with no flags"

# ---------------------------------------------------------------------------
# privacy preset
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset privacy --disable-analytics true
assert_true "privacy: analytics disabled" defaults_called_with "AutoSubmit -bool false"

# ---------------------------------------------------------------------------
# dotpkg_hotkey_disable
# ---------------------------------------------------------------------------
reset_logs
dotpkg_hotkey_disable spotlight
assert_true "hotkey_disable: spotlight ID 64" defaults_called_with "AppleSymbolicHotKeys -dict-add 64"
assert_true "hotkey_disable: spotlight ID 65" defaults_called_with "AppleSymbolicHotKeys -dict-add 65"

reset_logs
dotpkg_hotkey_disable mission-control
assert_true "hotkey_disable: mission-control ID 32" defaults_called_with "AppleSymbolicHotKeys -dict-add 32"
assert_true "hotkey_disable: mission-control ID 34" defaults_called_with "AppleSymbolicHotKeys -dict-add 34"

assert_false "hotkey_disable: unknown name returns 1" dotpkg_hotkey_disable unknown-hotkey

# ---------------------------------------------------------------------------
# dotpkg_hotkey_set_corner
# ---------------------------------------------------------------------------
reset_logs
dotpkg_hotkey_set_corner tl 3
assert_true "set_corner: tl key written"       defaults_called_with "wvous-tl-corner -int 3"
assert_true "set_corner: tl modifier written"  defaults_called_with "wvous-tl-modifier -int 0"

reset_logs
dotpkg_hotkey_set_corner br 10
assert_true "set_corner: br corner written"    defaults_called_with "wvous-br-corner -int 10"

assert_false "set_corner: unknown position returns 1" dotpkg_hotkey_set_corner center 0
assert_false "set_corner: missing args returns 1"     dotpkg_hotkey_set_corner

# ---------------------------------------------------------------------------
# Machine-local override sourcing
# ---------------------------------------------------------------------------
reset_logs
# Write a local override that calls defaults with a sentinel value
cat > "$DOTPKG_HOME/presets/keyboard.local.sh" <<'EOF'
defaults write NSGlobalDomain KeyRepeat -int 99
EOF

dotpkg_preset keyboard
assert_true "local override: sentinel defaults call present" defaults_called_with "KeyRepeat -int 99"

rm "$DOTPKG_HOME/presets/keyboard.local.sh"

# ---------------------------------------------------------------------------
# installed_presets tracked in state.json
# ---------------------------------------------------------------------------
reset_logs
dotpkg_preset finder
preset_count=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
print(len(s.get('installed_presets', [])))
")
assert_true "installed_presets: finder recorded" test "$preset_count" -ge 1

found=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
print('yes' if 'finder' in s.get('installed_presets', []) else 'no')
")
assert_eq "installed_presets: finder name stored" "$found" "yes"

# Idempotent — running finder twice doesn't duplicate entry
dotpkg_preset finder
dup_count=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
print(s.get('installed_presets', []).count('finder'))
")
assert_eq "installed_presets: finder not duplicated" "$dup_count" "1"

# ---------------------------------------------------------------------------
# state_add_bundle with stow_paths
# ---------------------------------------------------------------------------
state_add_bundle "testbundle" "local" ".zshrc .gitconfig"
stow_paths_out=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
match = [b for b in s['installed_bundles'] if b['name'] == 'testbundle']
print(' '.join(match[0]['stow_paths']) if match else '')
")
assert_eq "stow_paths: stored in state"    "$stow_paths_out" ".zshrc .gitconfig"

# Empty stow_paths (no stow dir)
state_add_bundle "nostow" "local" ""
empty_paths=$(python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
match = [b for b in s['installed_bundles'] if b['name'] == 'nostow']
print(len(match[0]['stow_paths']) if match else -1)
")
assert_eq "stow_paths: empty list when no stow" "$empty_paths" "0"

# ---------------------------------------------------------------------------
# _gum_* fallback — stdin not a tty in tests, gum absent -> safe defaults
# (type -P checks PATH only, not bash functions — so no fake gum in PATH yet)
# ---------------------------------------------------------------------------

# _gum_input: returns default when non-interactive and gum absent
got=$(_gum_input "prompt: " "mydefault")
assert_eq "gum_input: returns default when non-interactive" "$got" "mydefault"

got=$(_gum_input "prompt: " "")
assert_eq "gum_input: empty default returns empty string" "$got" ""

# _gum_confirm: returns 1 (no) when non-interactive and gum absent
assert_false "gum_confirm: returns 1 (no) when non-interactive" _gum_confirm "do something?"

# _gum_pager: passes content through when gum absent
pager_out=$(echo "hello pager" | _gum_pager)
assert_eq "gum_pager: content passes through without gum" "$pager_out" "hello pager"

# Install a fake gum script into PATH to test the "gum available" path
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/gum" <<'GUMEOF'
#!/usr/bin/env bash
case "$1" in
  input)
    shift
    while [[ $# -gt 0 ]]; do
      case "$1" in --value) echo "$2"; exit 0 ;; *) shift ;; esac
    done ;;
  confirm) exit 0 ;;
  pager)   cat ;;
esac
GUMEOF
chmod +x "$TEST_ROOT/bin/gum"
PATH="$TEST_ROOT/bin:$PATH"

got=$(_gum_input "prompt: " "gum-default")
assert_eq "gum_input: uses gum when available" "$got" "gum-default"

assert_true "gum_confirm: uses gum when available (returns 0)" _gum_confirm "ok?"

pager_out=$(echo "via gum" | _gum_pager)
assert_eq "gum_pager: passes content through gum pager" "$pager_out" "via gum"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: PASS=$_PASS FAIL=$_FAIL"
[[ $_FAIL -eq 0 ]]
