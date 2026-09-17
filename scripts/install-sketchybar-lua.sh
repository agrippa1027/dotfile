#!/usr/bin/env bash
set -euo pipefail

# SbarLua's Lua 5.5 update; keep this aligned with the installed Lua minor ABI.
revision=dba9cc421b868c918d5c23c408544a28aadf2f2f
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/sketchybar-lua.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
curl -fsSL "https://codeload.github.com/FelixKratz/SbarLua/tar.gz/$revision" \
  -o "$build_dir/source.tar.gz"
tar -xzf "$build_dir/source.tar.gz" -C "$build_dir"
make -C "$build_dir/SbarLua-$revision" install \
  INSTALL_DIR="$config_root/sketchybar/runtime"
printf '%s\n' "$revision" > "$config_root/sketchybar/runtime/SBARLUA_VERSION"
printf 'SbarLua installed for Lua 5.5 in %s\n' "$config_root/sketchybar/runtime"
