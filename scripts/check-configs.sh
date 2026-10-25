#!/usr/bin/env bash
set -euo pipefail

config_root="${XDG_CONFIG_HOME:-$HOME/.config}"

ok() {
  printf '[ok] %s\n' "$1"
}

die() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$2" ]] || die "$1 missing: $2"
  ok "$1 found"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command missing: $1"
}

assert_contains() {
  grep -Eq "$2" "$3" || die "$1"
  ok "$1"
}

require_file 'Archived AeroSpace config' "$config_root/aerospace/aerospace.toml"
require_file 'yabai config' "$config_root/yabai/yabairc"
require_file 'skhd config' "$config_root/skhd/skhdrc"
require_file 'Window shortcut helper' "$config_root/skhd/wm.sh"
require_file 'Ghostty config' "$config_root/ghostty/config"
require_file 'SketchyBar config' "$config_root/sketchybar/sketchybarrc"
require_file 'SketchyBar app icon font' "$config_root/sketchybar/vendor/app-font/sketchybar-app-font.ttf"
require_file 'SketchyBar app icon map' "$config_root/sketchybar/vendor/app-font/icon_map.lua"
require_file 'SketchyBar Lua entry point' "$config_root/sketchybar/init.lua"
require_file 'SbarLua runtime' "$config_root/sketchybar/runtime/sketchybar.so"
require_file 'tmux config' "$config_root/tmux/tmux.conf"
require_file 'Zsh config' "$config_root/.zshrc"
require_file 'Zsh secrets' "$config_root/zsh/secrets.zsh"
require_file 'fzf completion' '/opt/homebrew/opt/fzf/shell/completion.zsh'
require_file 'fzf key bindings' '/opt/homebrew/opt/fzf/shell/key-bindings.zsh'
require_file 'NVM loader' '/opt/homebrew/opt/nvm/nvm.sh'
require_file 'NVM completion' '/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm'
require_file 'Starship config' "$config_root/starship.toml"
require_file 'Zed settings' "$config_root/zed/settings.json"
require_file 'Yazi config' "$config_root/yazi/yazi.toml"

for required_command in yabai skhd sketchybar lua luac jq tmux zsh starship zoxide fzf yazi python3; do
  require_command "$required_command"
done
[[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]] || die 'Ghostty app is not installed'
[[ -x "$config_root/sketchybar/sketchybarrc" ]] || die 'SketchyBar launcher is not executable'
bash -n "$config_root/sketchybar/sketchybarrc"
luac -p "$config_root"/sketchybar/*.lua "$config_root"/sketchybar/lib/*.lua \
  "$config_root"/sketchybar/items/*.lua "$config_root"/sketchybar/items/widgets/*.lua \
  "$config_root/sketchybar/vendor/app-font/icon_map.lua"
lua - "$config_root/sketchybar" <<'LUA'
local root = arg[1]
package.path = root .. "/?.lua;" .. package.path
-- Load the native API explicitly; ./sketchybar/init.lua can otherwise shadow it.
package.preload.sketchybar = assert(package.loadlib(root .. "/runtime/sketchybar.so", "luaopen_sketchybar"))
assert(type(require("sketchybar").event_loop) == "function", "SbarLua runtime failed to load")
LUA
ok 'SketchyBar Lua syntax and runtime validate'
[[ "$HOME/.zshrc" -ef "$config_root/.zshrc" ]] || die "$HOME/.zshrc is not linked to the managed config"

python3 - "$config_root/aerospace/aerospace.toml" "$config_root/skhd/skhdrc" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as config_file:
    tomllib.load(config_file)

bindings = {}
for line in open(sys.argv[2]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    key, command = line.split(":", 1)
    key = " ".join(key.split())
    assert key not in bindings, f"Duplicate shortcut: {key}"
    assert command.strip(), f"Empty shortcut: {key}"
    bindings[key] = command.strip()
assert bindings["cmd - return"] == "/usr/bin/open -na Ghostty"
assert bindings["cmd + shift - return"] == "/usr/bin/open -a Firefox"
assert all(f"alt - {number}" in bindings for number in "1234567890a")
assert all(f"cmd - {key}" not in bindings for key in ("c", "v", "a", "q", "w", "space", "tab", "f", "s", "o", "k", "backspace"))
assert all('cmd' not in key.split(' - ')[0] for key, action in bindings.items() if 'yabai' in action or 'wm.sh' in action and not key.endswith(' - n'))
PY
bash -n "$config_root/yabai/yabairc" "$config_root/yabai/setup-spaces.sh" \
  "$config_root/yabai/setup-scripting-addition.sh" "$config_root/skhd/wm.sh"
ok 'Archived AeroSpace TOML, yabai shell config, and skhd bindings validate'

/Applications/Ghostty.app/Contents/MacOS/ghostty \
  +validate-config --config-file="$config_root/ghostty/config" >/dev/null 2>&1
ok 'Ghostty config validates'

tmux_socket="${TMPDIR:-/tmp}/omarchy-config-check-$$.sock"
cleanup_tmux() {
  if [[ -S "$tmux_socket" ]]; then
    tmux -S "$tmux_socket" kill-server >/dev/null 2>&1
  fi
  rm -f "$tmux_socket"
}
trap cleanup_tmux EXIT INT TERM
tmux -S "$tmux_socket" -f "$config_root/tmux/tmux.conf" new-session -d -s config-check
[[ "$(tmux -S "$tmux_socket" show-options -gv prefix)" == C-Space ]] || die 'tmux prefix is not C-Space'
cleanup_tmux
trap - EXIT INT TERM
ok 'tmux config loads in an isolated server'

assert_contains 'Ghostty titlebar is hidden' '^macos-titlebar-style[[:space:]]*=[[:space:]]*hidden$' "$config_root/ghostty/config"
assert_contains 'Ghostty emits Alt-Enter CSI-u' '^keybind[[:space:]]*=[[:space:]]*alt\+enter=' "$config_root/ghostty/config"
assert_contains 'Ghostty emits Alt-Shift-Enter CSI-u' '^keybind[[:space:]]*=[[:space:]]*alt\+shift\+enter=' "$config_root/ghostty/config"
assert_contains 'tmux uses Ctrl-Space prefix' '^set -g prefix C-Space$' "$config_root/tmux/tmux.conf"
assert_contains 'tmux supports direct vertical splits' '^bind -n M-Enter split-window -v' "$config_root/tmux/tmux.conf"
if grep -Eq '^set -g prefix2|^bind C-b' "$config_root/tmux/tmux.conf"; then
  die 'Legacy tmux prefix fallback remains configured'
fi
ok 'tmux has no legacy prefix fallback'

zsh -n "$config_root/.zshrc"
ok 'Zsh config parses'

ctrl_r_binding="$(zsh -ic 'bindkey -M viins "^R"' 2>/dev/null)"
[[ "$ctrl_r_binding" == '"^R" fzf-history-widget' ]] || \
  die "Ctrl-R is not bound to fzf history in viins: $ctrl_r_binding"
ok 'Ctrl-R opens fzf history in viins'

autosuggest_strategy="$(zsh -ic 'print -r -- ${(j: :)ZSH_AUTOSUGGEST_STRATEGY}' 2>/dev/null)"
[[ "$autosuggest_strategy" == 'history completion' ]] || \
  die "Zsh autosuggestion strategy is incomplete: $autosuggest_strategy"
ok 'Zsh autosuggestions fall back from history to completion'

docker_completion="$(zsh -ic 'print -r -- ${_comps[docker]-missing}' 2>/dev/null)"
[[ "$docker_completion" == '_docker' ]] || \
  die "Docker completion is not registered: $docker_completion"
ok 'Docker completion is registered'

docker_completion_file="$(zsh -ic 'completion_files=($^fpath/_docker(N)); print -r -- $completion_files[1]' 2>/dev/null)"
[[ "$docker_completion_file" == '/opt/homebrew/share/zsh/site-functions/_docker' ]] || \
  die "Docker completion does not resolve to Homebrew: $docker_completion_file"
ok 'Docker completion resolves to Homebrew'

docker_autosuggestion="$(zsh -ic '_zsh_autosuggest_strategy_completion "docker syst"; print -r -- "$suggestion"' 2>/dev/null)"
[[ "$docker_autosuggestion" == 'docker system' ]] || \
  die "Docker autosuggestion did not complete a subcommand: $docker_autosuggestion"
ok 'Docker subcommands produce completion-based autosuggestions'

STARSHIP_CONFIG="$config_root/starship.toml" starship explain >/dev/null
ok 'Starship config validates'

if grep -Eq 'p10k|powerlevel10k' "$config_root/.zshrc"; then
  die 'Powerlevel10k references remain in Zsh config'
fi
ok 'Zsh config is free of Powerlevel10k references'

if command -v nvim >/dev/null 2>&1; then
  nvim --headless '+qa' >/dev/null 2>&1
  ok 'Neovim starts headless'
fi

printf 'Validation complete.\n'
