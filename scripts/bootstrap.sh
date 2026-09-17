#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Install it first: https://brew.sh"
  exit 1
fi

echo "Installing core CLI tools..."
brew install git neovim tmux yazi btop fzf ripgrep fd starship zoxide stow deno bun nvm go pnpm python jq switchaudio-osx lua
brew tap FelixKratz/formulae
brew trust --formula felixkratz/formulae/sketchybar
brew install sketchybar
"$HOME/.config/scripts/install-sketchybar-lua.sh"
mkdir -p "$HOME/.nvm"

echo "Installing UI apps..."
brew install --cask aerospace ghostty raycast font-maple-mono-nf

zinit_home="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
echo "Ensuring Zinit is installed..."
if [[ ! -d "$zinit_home" ]]; then
  mkdir -p "$(dirname "$zinit_home")"
  git clone https://github.com/zdharma-continuum/zinit.git "$zinit_home"
fi

secrets_file="$HOME/.config/zsh/secrets.zsh"
if [[ -e "$secrets_file" && ! -f "$secrets_file" ]]; then
  echo "$secrets_file exists but is not a regular file." >&2
  exit 1
fi
if [[ ! -e "$secrets_file" ]]; then
  mkdir -p "$(dirname "$secrets_file")"
  install -m 600 /dev/null "$secrets_file"
fi
chmod 600 "$secrets_file"

if [[ -e "$HOME/.zshrc" && ! "$HOME/.zshrc" -ef "$HOME/.config/.zshrc" ]]; then
  echo "Existing ~/.zshrc is unmanaged; move or back it up before running bootstrap again." >&2
  exit 1
fi
ln -sfn "$HOME/.config/.zshrc" "$HOME/.zshrc"

echo "Bootstrap finished."
echo "Next: run ~/.config/scripts/check-configs.sh"
