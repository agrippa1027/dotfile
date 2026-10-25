#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
yabai_bin="${YABAI_BIN:-/opt/homebrew/bin/yabai}"

yb() { "$yabai_bin" -m "$@"; }

space_index() {
  yb query --spaces | jq -er --arg label "ws-$1" '
    first(.[] | select(.label == $label and .["is-native-fullscreen"] == false) | .index)'
}

# Stable native indices and explicit wraparound; native fullscreen is skipped.
cycle_space() {
  local destination
  destination=$(yb query --spaces | jq -er --arg direction "$1" '
    sort_by(.index) as $all |
    ($all | map(select(.["is-native-fullscreen"] == false))) as $spaces |
    ($all | map(select(.["has-focus"])) | first | .index) as $current |
    if $direction == "next" then
      ([$spaces[] | select(.index > $current)] | first // $spaces[0])
    else
      ([$spaces[] | select(.index < $current)] | last // $spaces[-1])
    end | .index // empty')
  yb space --focus "$destination"
}

cycle_display() {
  local destination
  destination=$(yb query --displays | jq -er --arg direction "$1" '
    sort_by(.index) as $displays |
    ($displays | map(.["has-focus"]) | index(true)) as $current |
    if $current == null then empty else
      $displays[(($current + (if $direction == "next" then 1 else -1 end)) + length) % length].index
    end')
  yb display --focus "$destination"
}

cycle_window() {
  local destination
  destination=$(yb query --windows --space | jq -er --arg direction "$1" '
    map(select(.["is-minimized"] == false and .["is-hidden"] == false and (.scratchpad == "" or .scratchpad == null))) |
    sort_by(.id) as $windows |
    ($windows | map(.["has-focus"]) | index(true)) as $current |
    if length == 0 then empty else
      $windows[(((if $current == null then (if $direction == "next" then -1 else 0 end) else $current end) +
        (if $direction == "next" then 1 else -1 end)) + length) % length].id
    end')
  yb window --focus "$destination"
}

scratch() {
  local scratch_id scratch_window attempt
  # Scratch labels are lost on daemon restart; recover the existing terminal by title.
  scratch_window=$(yb query --windows | jq -c '
    ([.[] | select(.scratchpad == "scratch")] +
     [.[] | select(.app == "Ghostty" and .title == "Scratchpad")]) | first // empty')
  if [[ -n "$scratch_window" ]]; then
    scratch_id=$(jq -r '.id' <<<"$scratch_window")
    if [[ "$(jq -r '.scratchpad' <<<"$scratch_window")" == scratch ]]; then
      yb window --toggle scratch
    else
      yb window "$scratch_id" --scratchpad scratch
      yb window "$scratch_id" --grid 8:8:1:1:6:6
      yb window --focus "$scratch_id"
    fi
    return
  fi

  /usr/bin/open -na Ghostty --args --title=Scratchpad
  # The yabai title rule assigns this new terminal to scratch; wait for AX creation.
  for ((attempt = 0; attempt < 30; attempt++)); do
    scratch_window=$(yb query --windows | jq -c 'first(.[] | select(.app == "Ghostty" and .title == "Scratchpad")) // empty')
    if [[ -n "$scratch_window" ]]; then
      scratch_id=$(jq -r '.id' <<<"$scratch_window")
      if [[ "$(jq -r '.scratchpad' <<<"$scratch_window")" != scratch ]]; then
        yb window "$scratch_id" --scratchpad scratch
      fi
      yb window "$scratch_id" --grid 8:8:1:1:6:6
      yb window --focus "$scratch_id"
      return
    fi
    /bin/sleep 0.1
  done
  printf 'Scratchpad terminal did not become available.\n' >&2
  return 1
}

case "${1:-}" in
  space)
    destination=$(space_index "${2:?Missing space label}")
    yb space --focus "$destination"
    ;;
  move)
    destination=$(space_index "${2:?Missing space label}")
    yb window --space "$destination"
    if [[ "${3:-}" == follow ]]; then yb space --focus "$destination"; fi
    ;;
  cycle-space) cycle_space "${2:?Missing direction}" ;;
  cycle-display) cycle_display "${2:?Missing direction}" ;;
  move-space-display)
    space=$(yb query --spaces --space)
    space_id=$(jq -er '.id' <<<"$space")
    source_display=$(jq -er '.display' <<<"$space")
    destination=$(yb query --displays | jq -er --argjson source "$source_display" '
      sort_by(.index) as $displays |
      ($displays | map(.index) | index($source)) as $current |
      if $current == null then empty else
        $displays[($current + 1) % length].index
      end')
    if [[ "$destination" != "$source_display" ]]; then
      # macOS requires at least one ordinary desktop to remain on each display.
      if [[ $(yb query --spaces --display "$source_display" | jq '[.[] | select(.["is-native-fullscreen"] == false)] | length') -lt 2 ]]; then
        yb space --create "$source_display"
        for _ in 1 2 3 4 5 6 7 8 9 10; do
          [[ $(yb query --spaces --display "$source_display" | jq '[.[] | select(.["is-native-fullscreen"] == false)] | length') -gt 1 ]] && break
          sleep 0.1
        done
      fi
      # Native indices change when desktops move; the Space ID stays stable.
      index=$(yb query --spaces | jq -er --argjson id "$space_id" 'first(.[] | select(.id == $id) | .index)')
      yb space "$index" --display "$destination"
      space=$(yb query --spaces | jq -ec --argjson id "$space_id" 'first(.[] | select(.id == $id))')
      if ! jq -e '.["has-focus"]' <<<"$space" >/dev/null; then
        yb space --focus "$(jq -er '.index' <<<"$space")"
      fi
    fi
    ;;
  cycle-window) cycle_window "${2:?Missing direction}" ;;
  focus)
    yb window --focus "${2:?Missing direction}" 2>/dev/null || yb display --focus "$2"
    ;;
  sticky)
    window=$(yb query --windows --window)
    window_id=$(jq -er '.id' <<<"$window")
    if jq -e '.["is-sticky"]' <<<"$window" >/dev/null; then
      yb window "$window_id" --toggle sticky
      yb window "$window_id" --toggle float
    else
      if ! jq -e '.["is-floating"]' <<<"$window" >/dev/null; then
        yb window "$window_id" --toggle float
        yb window "$window_id" --grid 8:8:1:1:6:6
      fi
      yb window "$window_id" --toggle sticky
    fi
    ;;
  opacity)
    window=$(yb query --windows --window)
    window_id=$(jq -er '.id' <<<"$window")
    if jq -e '.opacity >= 0.99' <<<"$window" >/dev/null; then
      yb window "$window_id" --opacity 0.90
    else
      yb window "$window_id" --opacity 1.0
    fi
    ;;
  resize)
    delta="${3:?Missing resize delta}"
    case "$delta" in 40|-40) ;; *) exit 2 ;; esac
    if [[ "${2:-}" == width ]]; then
      yb window --resize "right:$delta:0" 2>/dev/null || yb window --resize "left:$((-delta)):0"
    elif [[ "${2:-}" == height ]]; then
      yb window --resize "bottom:0:$delta" 2>/dev/null || yb window --resize "top:0:$((-delta))"
    else
      exit 2
    fi
    ;;
  scratch) scratch ;;
  editor)
    if command -v nvim >/dev/null 2>&1; then
      /usr/bin/open -na Ghostty --args -e "$(command -v nvim)"
    else
      /usr/bin/open -a Zed
    fi
    ;;
  *)
    printf 'Usage: %s {space LABEL|move LABEL [follow]|move-space-display|cycle-space next/prev|cycle-display next/prev|cycle-window next/prev|focus DIRECTION|sticky|opacity|resize width/height 40/-40|scratch|editor}\n' "${0##*/}" >&2
    exit 2
    ;;
esac