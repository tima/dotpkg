#!/usr/bin/env bash
set -euo pipefail

DOTPKG_REPO="${DOTPKG_REPO:-tappnel/dotfiles-mgr}"
DOTPKG_HOME="${DOTPKG_HOME:-$HOME/.dotpkg}"
PROFILE="${1:-}"
if ! xcode-select -p &>/dev/null; then
  echo "==> Installing Xcode Command Line Tools..."
  echo "    A dialog will appear — click Install and wait for it to finish."
  xcode-select --install
  until xcode-select -p &>/dev/null; do sleep 5; done
  echo "    Xcode CLT installed."
fi
if ! command -v brew &>/dev/null; then
  echo "==> Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"

echo "==> Installing stow and gum..."
brew install stow gum
if [[ -d "$DOTPKG_HOME" ]]; then
  echo "==> Updating dotpkg repo at $DOTPKG_HOME..."
  git -C "$DOTPKG_HOME" pull --quiet
else
  echo "==> Cloning dotpkg to $DOTPKG_HOME..."
  git clone --quiet "https://github.com/${DOTPKG_REPO}.git" "$DOTPKG_HOME"
fi
chmod +x "$DOTPKG_HOME/dotpkg"

echo "==> Linking dotpkg to /usr/local/bin/dotpkg..."
mkdir -p /usr/local/bin
ln -sf "$DOTPKG_HOME/dotpkg" /usr/local/bin/dotpkg
case "${SHELL##*/}" in
  bash) SHELL_PROFILE="$HOME/.bash_profile" ;;
  zsh)  SHELL_PROFILE="$HOME/.zprofile" ;;
  *)    SHELL_PROFILE="$HOME/.profile" ;;
esac
if ! grep -q 'brew shellenv' "$SHELL_PROFILE" 2>/dev/null; then
  printf '\n# Homebrew\neval "$(/opt/homebrew/bin/brew shellenv)"\n' >> "$SHELL_PROFILE"
fi

echo ""
echo "==> Bootstrap complete. Running dotpkg init..."
echo ""
[[ -n "$PROFILE" ]] && "$DOTPKG_HOME/dotpkg" init --profile "$PROFILE" || "$DOTPKG_HOME/dotpkg" init
echo ""
echo "==> Done. Open a new shell or run: source $SHELL_PROFILE"
