#!/usr/bin/env bash
# Open a timestamped daily entry in the floating Zed Log workspace.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

log_dir="${LOG_DIR:-$HOME/Log}"
zed_bin="${ZED_BIN:-/usr/local/bin/zed}"
yabai_bin="${YABAI_BIN:-/opt/homebrew/bin/yabai}"
yb() { "$yabai_bin" -m "$@"; }
log_window() {
  yb query --windows | jq -c 'first(.[] | select(.app == "Zed" and (.title | test("^Log( —|$)")))) // empty'
}

# Ignore overlapping key repeats while the window is opening.
lock_dir="${TMPDIR:-/tmp}/zed-log-$UID.lock"
mkdir "$lock_dir" 2>/dev/null || exit 0
trap 'rmdir "$lock_dir"' EXIT

# Capture the destination before activating Zed changes desktop focus.
space=$(yb query --spaces --space | jq -er '.index')
window=$(log_window)
if [[ -n "$window" ]]; then
  window_id=$(jq -er '.id' <<<"$window")
  if jq -e '.["is-minimized"]' <<<"$window" >/dev/null; then
    yb window "$window_id" --deminimize
  fi
  if ! jq -e '.["is-floating"]' <<<"$window" >/dev/null; then
    yb window "$window_id" --toggle float
  fi
  if [[ $(jq -r '.space' <<<"$window") != "$space" ]]; then
    yb window "$window_id" --space "$space"
  fi
  yb window --focus "$window_id"
fi

mkdir -p "$log_dir"
# One date invocation keeps filename, title and time consistent across midnight.
IFS='|' read -r day stamp day_number month year < <(date '+%Y-%m-%d|%H:%M|%d|%B|%Y')
file="$log_dir/$day.md"
day_number=$((10#$day_number))
case "$day_number" in
  11|12|13) suffix=th ;;
  *1) suffix=st ;;
  *2) suffix=nd ;;
  *3) suffix=rd ;;
  *) suffix=th ;;
esac
if [[ ! -s "$file" ]]; then
  printf '# %s%s %s %s\n' "$day_number" "$suffix" "$month" "$year" >> "$file"
fi
printf '\n\n## %s\n\n' "$stamp" >> "$file"
line=$(awk 'END { print NR }' "$file")

if [[ -n "$window" ]]; then
  # Focus first: --add targets that workspace and keeps Log as the project root.
  "$zed_bin" -a "$file:$line:1"
else
  "$zed_bin" -n "$log_dir" "$file:$line:1"
fi

for ((attempt = 0; attempt < 50; attempt++)); do
  window=$(log_window)
  [[ -n "$window" ]] && break
  sleep 0.1
done
if [[ -z "$window" ]]; then
  printf 'Entry created in %s, but the Zed Log window was not found.\n' "$file" >&2
  exit 1
fi
window_id=$(jq -er '.id' <<<"$window")
if ! jq -e '.["is-floating"]' <<<"$window" >/dev/null; then
  yb window "$window_id" --toggle float
fi
if [[ $(jq -r '.space' <<<"$window") != "$space" ]]; then
  yb window "$window_id" --space "$space"
fi
yb window "$window_id" --grid 10:10:2:1:6:8
yb window --focus "$window_id"
