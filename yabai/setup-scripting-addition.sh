#!/bin/bash
# Run with sudo after every yabai upgrade: the rule pins the installed binary hash.
set -euo pipefail
[[ $EUID -eq 0 ]] || { printf 'Run: sudo bash %q\n' "$0" >&2; exit 1; }
case "${1:-}" in ''|--refresh) ;; *) exit 2 ;; esac
binary=/opt/homebrew/bin/yabai
target=/private/etc/sudoers.d/yabai
[[ -x "$binary" && ! -L "$target" ]] || { printf 'Unexpected yabai binary or sudoers symlink\n' >&2; exit 1; }
digest=$(/usr/bin/shasum -a 256 "$binary" | /usr/bin/awk '{print $1}')
candidate=$(/usr/bin/mktemp /private/tmp/yabai-sudoers.XXXXXX)
trap '/bin/rm -f "$candidate"' EXIT
printf 'afsalahamed ALL=(root) NOPASSWD: sha256:%s %s --load-sa\n' "$digest" "$binary" > "$candidate"
/usr/sbin/visudo -cf "$candidate"
if [[ -e "$target" ]] && ! /usr/bin/cmp -s "$candidate" "$target"; then
  /bin/cp -p "$target" "$target.before-rice.$(/bin/date +%Y%m%d-%H%M%S)"
fi
/usr/bin/install -o root -g wheel -m 0440 "$candidate" "$target"
# Source builds can contain a new payload without changing its bundle version.
if [[ "${1:-}" == --refresh ]]; then
  "$binary" --uninstall-sa
fi
SUDO_UID=$(/usr/bin/id -u afsalahamed)
export SUDO_UID
"$binary" --load-sa
