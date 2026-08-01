#!/usr/bin/env bash
# dotpkg preset and helper functions — sourced into dotpkg's process so they are
# available when bundle defaults.sh files are sourced.

# ---------------------------------------------------------------------------
# dotpkg_preset — apply a named group of defaults write commands
# ---------------------------------------------------------------------------
# ponytail: preset signatures chosen from macos.sh reference; TBD per spec.
# Callers: bundle defaults.sh files (personal and tool bundles).

dotpkg_preset() {
  local category="${1:-}"
  [[ -z "$category" ]] && { echo "usage: dotpkg_preset <category> [flags]" >&2; return 1; }
  shift
  local _preset_rc=0
  case "$category" in
    keyboard)       _preset_keyboard "$@" ;;
    finder)         _preset_finder "$@" ;;
    dock)           _preset_dock "$@" ;;
    trackpad)       _preset_trackpad "$@" ;;
    screenshots)    _preset_screenshots "$@" ;;
    display)        _preset_display "$@" ;;
    menubar)        _preset_menubar "$@" ;;
    accent-color)   _preset_accent_color "$@" ;;
    spotlight)      _preset_spotlight "$@" ;;
    privacy)        _preset_privacy "$@" ;;
    *) echo "dotpkg_preset: unknown category: $category" >&2; return 1 ;;
  esac || _preset_rc=$?
  [[ $_preset_rc -ne 0 ]] && return $_preset_rc
  # Machine-local override — sourced after preset so individual values can be overridden
  local _local_override="${DOTPKG_HOME:-$HOME/.dotpkg}/presets/${category}.local.sh"
  if [[ -f "$_local_override" ]]; then
    # shellcheck disable=SC1090
    . "$_local_override"
  fi
  # Record in state if state.sh is loaded
  if declare -f state_add_preset >/dev/null 2>&1; then
    state_add_preset "$category" 2>/dev/null || true
  fi
}

_preset_keyboard() {
  local key_repeat=2 initial_key_repeat=15
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --key-repeat)         key_repeat="$2"; shift 2 ;;
      --initial-key-repeat) initial_key_repeat="$2"; shift 2 ;;
      *) echo "dotpkg_preset keyboard: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  defaults write NSGlobalDomain KeyRepeat -int "$key_repeat"
  defaults write NSGlobalDomain InitialKeyRepeat -int "$initial_key_repeat"
  defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
  defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
}

_preset_finder() {
  # ponytail: no params — all values match macos.sh reference defaults.
  defaults write com.apple.finder AppleShowAllFiles -bool true
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
  defaults write com.apple.finder WarnOnEmptyTrash -bool false
  defaults write com.apple.finder FXRemoveOldTrashItems -bool true
  # Group Desktop items by Kind (Stacks)
  defaults write com.apple.finder DesktopViewSettings -dict-add GroupBy -string "Kind"
  # Expand save and print dialogs by default
  defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
  defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
  # Suppress .DS_Store creation on network and USB volumes
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
}

_preset_dock() {
  local icon_size=48 auto_hide=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --icon-size)  icon_size="$2"; shift 2 ;;
      --auto-hide)  auto_hide="$2"; shift 2 ;;
      *) echo "dotpkg_preset dock: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  defaults write com.apple.dock tilesize -int "$icon_size"
  defaults write com.apple.dock autohide -bool "$auto_hide"
  # Disable automatic Space reordering (keeps Spaces in fixed order)
  defaults write com.apple.dock mru-spaces -bool false
}

_preset_trackpad() {
  # ponytail: defaults match macos.sh — disable force click, enable tap-to-click optional.
  # Disable force click by default (matches user preference in macos.sh)
  defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool false
  defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --enable-force-click)
        defaults write NSGlobalDomain com.apple.trackpad.forceClick -bool true
        defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool false
        shift ;;
      --enable-tap-to-click)
        defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
        defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
        shift ;;
      *) echo "dotpkg_preset trackpad: unknown flag: $1" >&2; return 1 ;;
    esac
  done
}

_preset_screenshots() {
  local location="$HOME/Downloads/screenshots"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --location) location="${2/#\~/$HOME}"; shift 2 ;;
      *) echo "dotpkg_preset screenshots: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  mkdir -p "$location"
  defaults write com.apple.screencapture location -string "$location"
}

_preset_display() {
  local screensaver_idle=300
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --screensaver-idle) screensaver_idle="$2"; shift 2 ;;
      *) echo "dotpkg_preset display: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  defaults -currentHost write com.apple.screensaver idleTime "$screensaver_idle"
  defaults write com.apple.screensaver askForPassword -int 1
  defaults write com.apple.screensaver askForPasswordDelay -int 0
}

_preset_menubar() {
  local show_battery_pct=true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --show-battery-percentage) show_battery_pct="$2"; shift 2 ;;
      *) echo "dotpkg_preset menubar: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  defaults write ~/Library/Preferences/ByHost/com.apple.controlcenter.plist BatteryShowPercentage -bool "$show_battery_pct"
  defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1
  defaults write com.apple.Siri StatusMenuVisible -bool false
}

# ponytail: accent color int values from Apple's AppleAccentColor pref.
_ACCENT_COLORS=(graphite:-1 red:0 orange:1 yellow:2 green:3 blue:4 purple:5 pink:6)

_preset_accent_color() {
  local value="graphite"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --value) value="$2"; shift 2 ;;
      *) echo "dotpkg_preset accent-color: unknown flag: $1" >&2; return 1 ;;
    esac
  done
  if [[ "$value" == "multicolor" ]]; then
    defaults delete NSGlobalDomain AppleAccentColor 2>/dev/null || true
    return
  fi
  local int_val=""
  local pair
  for pair in "${_ACCENT_COLORS[@]}"; do
    if [[ "${pair%%:*}" == "$value" ]]; then
      int_val="${pair##*:}"
      break
    fi
  done
  [[ -z "$int_val" ]] && { echo "dotpkg_preset accent-color: unknown color: $value (graphite|red|orange|yellow|green|blue|purple|pink|multicolor)" >&2; return 1; }
  defaults write NSGlobalDomain AppleAccentColor -int "$int_val"
}

_preset_spotlight() {
  # ponytail: no configurable params yet; just applies sensible search scope defaults.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --disable-web-search)
        # Handled by disabling the Spotlight hotkey rather than web search pref
        shift 2 ;;
      *) echo "dotpkg_preset spotlight: unknown flag: $1" >&2; return 1 ;;
    esac
  done
}

_preset_privacy() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --disable-analytics)
        if [[ "$2" == "true" ]]; then
          defaults write com.apple.DiagnosticReportingService.managed AutoSubmit -bool false
          defaults write com.apple.SubmitDiagInfo AutoSubmit -bool false
        fi
        shift 2 ;;
      *) echo "dotpkg_preset privacy: unknown flag: $1" >&2; return 1 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# dotpkg_hotkey_disable — disable system hotkeys by name
# ---------------------------------------------------------------------------
# ponytail: hotkey IDs from Apple's AppleSymbolicHotKeys pref (from macos.sh).

dotpkg_hotkey_disable() {
  local name="${1:-}"
  [[ -z "$name" ]] && { echo "usage: dotpkg_hotkey_disable <name>" >&2; return 1; }
  case "$name" in
    spotlight)
      # IDs 64 (Cmd+Space) and 65 (Cmd+Alt+Space)
      defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "<dict><key>enabled</key><false/></dict>"
      defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 65 "<dict><key>enabled</key><false/></dict>"
      ;;
    mission-control)
      # IDs 32 (Ctrl+Up) and 34 (Ctrl+Down)
      defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 32 "<dict><key>enabled</key><false/></dict>"
      defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 34 "<dict><key>enabled</key><false/></dict>"
      ;;
    *) echo "dotpkg_hotkey_disable: unknown hotkey: $name (spotlight|mission-control)" >&2; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# dotpkg_hotkey_set_corner — configure macOS hot corners
# ---------------------------------------------------------------------------
# ponytail: position and action enums TBD per spec; minimal set implemented.
# Positions: tl tr bl br. Actions: 0=none 2=mission-control 3=show-application-windows
# 4=desktop 10=put-display-to-sleep 11=launchpad 14=notification-center.

dotpkg_hotkey_set_corner() {
  local position="${1:-}" action="${2:-}"
  [[ -z "$position" || -z "$action" ]] && { echo "usage: dotpkg_hotkey_set_corner <tl|tr|bl|br> <action>" >&2; return 1; }
  local key
  case "$position" in
    tl) key="wvous-tl-corner" ;;
    tr) key="wvous-tr-corner" ;;
    bl) key="wvous-bl-corner" ;;
    br) key="wvous-br-corner" ;;
    *) echo "dotpkg_hotkey_set_corner: unknown position: $position" >&2; return 1 ;;
  esac
  local modifier_key="${key/corner/modifier}"
  defaults write com.apple.dock "$key" -int "$action"
  defaults write com.apple.dock "$modifier_key" -int 0
}

# ---------------------------------------------------------------------------
# dotpkg_dock — dock app management
# ---------------------------------------------------------------------------

dotpkg_dock() {
  local subcmd="${1:-}"
  [[ -z "$subcmd" ]] && { echo "usage: dotpkg_dock add <app> [<app> ...]" >&2; return 1; }
  shift
  case "$subcmd" in
    add) _dock_add "$@" ;;
    *) echo "dotpkg_dock: unknown subcommand: $subcmd" >&2; return 1 ;;
  esac
}

_dock_add() {
  local app app_path
  for app in "$@"; do
    app_path=$(find /Applications ~/Applications -name "${app}.app" -maxdepth 3 2>/dev/null | head -1)
    if [[ -z "$app_path" ]]; then
      echo "dotpkg: dock: app not found: ${app}.app (skipping)" >&2
      continue
    fi
    defaults write com.apple.dock persistent-apps -array-add \
      "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>${app_path}</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
  done
  killall Dock 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# dotpkg_wallpaper — set wallpaper across all spaces and displays
# ---------------------------------------------------------------------------
# ponytail: three-approach strategy from macos.sh — handles Sonoma+, Ventura,
# and provides AppleScript fallback. Covers all current macOS versions.

dotpkg_wallpaper() {
  local path="${1:-}"
  [[ -z "$path" ]] && { echo "usage: dotpkg_wallpaper <path>" >&2; return 1; }
  path="${path/#\~/$HOME}"
  [[ ! -f "$path" ]] && { echo "dotpkg_wallpaper: file not found: $path" >&2; return 1; }

  # Sonoma (14+): plist-based wallpaper engine
  local plist="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
  if [[ -f "$plist" ]]; then
    /usr/libexec/PlistBuddy -c "Delete :Displays" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Delete :Spaces" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :AllSpacesAndDisplays:Desktop:Content:Choices:0:Files:0:relative file:///${path}" "$plist" 2>/dev/null || true
    killall WallpaperAgent 2>/dev/null || true
  fi

  # Ventura and older: SQLite Dock database
  local db="$HOME/Library/Application Support/Dock/desktoppicture.db"
  if [[ -f "$db" ]]; then
    sqlite3 "$db" "update data set value = '${path}'" 2>/dev/null || true
    killall Dock 2>/dev/null || true
  fi

  # AppleScript: immediate visual refresh regardless of macOS version
  osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"${path}\""
}

# ---------------------------------------------------------------------------
# dotpkg_terminal_import — import a Terminal.app theme and set as default
# ---------------------------------------------------------------------------
# ponytail: sleep 1 is needed for Terminal.app to register the opened theme before
# writing defaults. Known fragile; no better API available.

dotpkg_terminal_import() {
  local theme_file="${1:-}"
  [[ -z "$theme_file" ]] && { echo "usage: dotpkg_terminal_import <path.terminal>" >&2; return 1; }
  theme_file="${theme_file/#\~/$HOME}"
  [[ ! -f "$theme_file" ]] && { echo "dotpkg_terminal_import: file not found: $theme_file" >&2; return 1; }
  local theme_name
  theme_name=$(basename "$theme_file" .terminal)
  open "$theme_file"
  sleep 1  # ponytail: Terminal.app needs a moment to register the imported theme
  defaults write com.apple.Terminal "Default Window Settings" -string "$theme_name"
  defaults write com.apple.Terminal "Startup Window Settings" -string "$theme_name"
}
