#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [--dry-run]\n' "${0##*/}"
}

dry_run=false
case "${1:-}" in
  '') ;;
  --dry-run) dry_run=true ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.config-backups}"
stamp="$(date +%Y%m%d-%H%M%S)"
archive="$backup_dir/omarchy-macos-$stamp.tar.gz"
manifest="$archive.manifest.txt"
checksum="$archive.sha256"

backup_items=(
  .config/.zshrc
  .config/aerospace
  .config/yabai
  .config/skhd
  .config/sketchybar
  .config/borders
  .config/ghostty
  .config/tmux
  .config/starship.toml
  .config/zed/settings.json
  .config/zed/keymap.json
  .config/theme
  .config/scripts
)

for backup_item in "${backup_items[@]}"; do
  [[ -e "$HOME/$backup_item" ]] || {
    printf 'Required backup path is missing: %s\n' "$backup_item" >&2
    exit 1
  }
done

if $dry_run; then
  printf 'Would create: %s\n' "$archive"
  printf 'Included paths:\n'
  printf '  %s\n' "${backup_items[@]}"
  exit 0
fi

umask 077
mkdir -p "$backup_dir"
tar \
  --exclude='.DS_Store' \
  --exclude='*/__pycache__' \
  --exclude='*.pyc' \
  --exclude='.config/tmux/plugins' \
  -czf "$archive" -C "$HOME" "${backup_items[@]}"
tar -tzf "$archive" >"$manifest"
shasum -a 256 "$archive" >"$checksum"
gzip -t "$archive"

printf 'Backup created: %s\n' "$archive"
printf 'Manifest: %s\n' "$manifest"
printf 'Checksum: %s\n' "$checksum"
