#!/usr/bin/env bash
set -euo pipefail
# bootstrap.sh — takes a blank Apple Silicon Mac to dotpkg-managed.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tappnel/dotfiles-mgr/main/bootstrap.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/tappnel/dotfiles-mgr/main/bootstrap.sh | bash -s workstation

DOTPKG_REPO="${DOTPKG_REPO:-tappnel/dotfiles-mgr}"
DOTPKG_HOME="${DOTPKG_HOME:-$HOME/.dotpkg}"
PROFILE="${1:-}"

# ---------------------------------------------------------------------------
# 1. Xcode Command Line Tools (provides git, cc)
# ---------------------------------------------------------------------------
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools..."
  echo "    A dialog will appear — click Install and wait for it to finish."
  xcode-select --install
  # Poll until CLT appear (the install is GUI-driven)
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
  echo "    Xcode CLT installed."
fi

# ---------------------------------------------------------------------------
# 2. Homebrew
# ---------------------------------------------------------------------------
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Ensure brew is on PATH (Apple Silicon path; Intel falls back to /usr/local)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ---------------------------------------------------------------------------
# 3. Required tools
# ---------------------------------------------------------------------------
echo "==> Installing stow and gum..."
brew install stow gum

# ---------------------------------------------------------------------------
# 4. Clone dotpkg repo to ~/.dotpkg/
# ---------------------------------------------------------------------------
if [[ -d "$DOTPKG_HOME" ]]; then
  echo "==> Updating dotpkg repo at $DOTPKG_HOME..."
  git -C "$DOTPKG_HOME" pull --quiet
else
  echo "==> Cloning dotpkg to $DOTPKG_HOME..."
  git clone --quiet "https://github.com/${DOTPKG_REPO}.git" "$DOTPKG_HOME"
fi

chmod +x "$DOTPKG_HOME/dotpkg"

# ---------------------------------------------------------------------------
# 5. Symlink dotpkg to /usr/local/bin/dotpkg
# ---------------------------------------------------------------------------
echo "==> Linking dotpkg to /usr/local/bin/dotpkg..."
mkdir -p /usr/local/bin
ln -sf "$DOTPKG_HOME/dotpkg" /usr/local/bin/dotpkg

# Add Homebrew to shell profile if not already there (new machines)
SHELL_PROFILE="$HOME/.zprofile"
if ! grep -q 'brew shellenv' "$SHELL_PROFILE" 2>/dev/null; then
  printf '\n# Homebrew\neval "$(/opt/homebrew/bin/brew shellenv)"\n' >> "$SHELL_PROFILE"
fi

# ---------------------------------------------------------------------------
# 6. Hand off to dotpkg init
# ---------------------------------------------------------------------------
echo ""
echo "==> Bootstrap complete. Running dotpkg init..."
echo ""

if [[ -n "$PROFILE" ]]; then
  "$DOTPKG_HOME/dotpkg" init --profile "$PROFILE"
else
  "$DOTPKG_HOME/dotpkg" init
fi

echo ""
echo "==> Done. Open a new shell or run: source ~/.zprofile"
