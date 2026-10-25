#!/bin/bash
# Idempotently label existing desktops before creating new ones. Never destroys Spaces.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/bin:/bin"
case "${1:-}" in ''|--arrange) ;; *) exit 2 ;; esac

displays=$(yabai -m query --displays)
# The larger external monitor hosts the numbered workspaces; the laptop gets a.
primary=$(jq -r 'max_by(.frame.w * .frame.h).index' <<< "$displays")
secondary=$(jq -r --argjson primary "$primary" 'map(select(.index != $primary)) | .[0].index // $primary' <<< "$displays")

for label in 1 2 3 4 5 6 7 8 9 0 a; do
  native_label="ws-$label"
  spaces=$(yabai -m query --spaces)
  display=$primary
  [[ "$label" != a ]] || display=$secondary
  existing=$(jq -r --arg label "$native_label" 'first(.[] | select(.label == $label and .["is-native-fullscreen"] == false)) // empty' <<< "$spaces")
  if [[ -n "$existing" ]]; then
    if [[ "${1:-}" == --arrange && "$(jq -r .display <<< "$existing")" != "$display" ]]; then
      yabai -m space "$(jq -r .index <<< "$existing")" --display "$display"
    fi
    continue
  fi
  index=$(jq -r --argjson display "$display" '[.[] | select(.display == $display and .label == "" and .["is-native-fullscreen"] == false)] | sort_by(.index) | .[0].index // empty' <<< "$spaces")
  if [[ -z "$index" ]]; then
    yabai -m space --create "$display"
    # Space creation notifications can arrive after the command returns.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      spaces=$(yabai -m query --spaces)
      index=$(jq -r --argjson display "$display" '[.[] | select(.display == $display and .label == "" and .["is-native-fullscreen"] == false)] | sort_by(.index) | .[-1].index // empty' <<< "$spaces")
      [[ -z "$index" ]] || break
      sleep 0.1
    done
  fi
  [[ -n "$index" ]] || { printf 'No native Space available for label %s\n' "$label" >&2; exit 1; }
  yabai -m space "$index" --label "$native_label"
done
