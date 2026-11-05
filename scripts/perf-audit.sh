#!/usr/bin/env bash
set -euo pipefail

echo "== Shell startup timing =="
if command -v zsh >/dev/null 2>&1; then
  /usr/bin/time zsh -i -c exit
else
  echo "zsh not found"
fi

echo
echo "== Top memory consumers =="
ps -axo pid,%mem,%cpu,comm | sort -k2 -nr | head -n 15

echo
echo "== Launch agents count =="
launchctl list | wc -l | xargs echo "loaded agents/services:"

echo
echo "== Config disk usage =="
du -sh "${XDG_CONFIG_HOME:-$HOME/.config}" 2>/dev/null | sed 's/^/  /'

echo
echo "== Battery + thermal snapshot =="
pmset -g batt | sed 's/^/  /'
pmset -g therm | sed 's/^/  /'

echo
echo "== Done =="
