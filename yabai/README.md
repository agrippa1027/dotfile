# Hubbamax yabai desktop

The desktop uses yabai for native macOS Spaces, skhd for global shortcuts,
and SketchyBar for the edge-to-edge Omarchy-style status bar. Retired AeroSpace
and JankyBorders configurations have been removed.

The next phase follows the [small look-and-feel milestones](MILESTONES.md),
starting with Option-drag tile rearrangement.
The [milestone 1 native fix and live check](M1-DRAG.md) record the first concrete
drag-placement regression and its correction in the personal yabai fork.
The [performance audit](PERFORMANCE.md) records measured CPU/memory usage and
the Accessibility lifetime fix now included in the active M2 build.
The [active M2 resize build](M2-NATIVE.md) runs entirely in yabai's C handlers;
its one-time activation and measurement tools are separate from everyday input.

## Appearance and workspaces

- 10px window gaps and padding on every side; 30px reserved for SketchyBar
  plus 10px of top padding between the bar and app windows.
- Tinted translucent Hubbamax bar, compact numbered Spaces, a square for each display's
  visible tiled Space (triangle for floating), and dimmed empty Spaces.
- Focused windows: 100% opacity; inactive: 96%, transitioning over 0.15 seconds.
  Firefox and video players (IINA, Stremio, VLC, mpv, QuickTime Player) stay at
  100% opacity even when unfocused, so video content does not become transparent.
- Window move/resize animations are disabled to avoid a CoreVideo display-link
  deadlock observed after sleep/display reconfiguration.
- Shadows on floating windows; tiled windows have no shadows.
- New numbered Spaces 1–9 and 0 start on the largest display; a starts on the other
  display. Existing labeled Spaces keep their current monitor assignments across
  reloads and docking. Their order is repaired within each display. Restoring the
  original monitor arrangement is an explicit opt-in:
  `~/.config/yabai/setup-spaces.sh --arrange`.
- Firefox/Chrome → 1, Zed → 2, Obsidian → 3, calibre → 4, Bruno → 6,
  Discord → 7, regular Ghostty terminals → 9 (and follow focus). The scratchpad
  remains separate. Finder, settings, messaging, and utility dialogs float.

Internal labels use `ws-1` through `ws-9`, `ws-0`, and `ws-a` because yabai rejects
purely numeric labels. The bar and shortcuts translate these to their short names.
Command+A stays Select All; Option+A focuses Space a.

See [the shortcut reference](../skhd/README.md).

## Strict Space ordering

Managed Spaces follow `1, 2, 3, 4, 5, 6, 7, 8, 9, 0, a` on each display.
Ordering preserves Space identities, monitor assignments and window membership.
Unnamed and other unmanaged desktops remain after the managed Spaces, in their
previous relative order; they are not deleted. Native fullscreen Spaces are
never selected as move sources or destinations.

Mission Control's recent-use rearrangement is disabled. Configuration setup and
Space/display lifecycle signals repair ordering, including after leaving Mission
Control or moving a Space to another display. Docking preserves existing monitor
assignments. `order-spaces.py` uses fresh native indices for each move and a lock
to coalesce overlapping repair requests.

Option+N/P cycles managed labels in canonical order across monitors, skipping
native fullscreen and unmanaged desktops. Direct shortcuts, bar clicks and app
routing use stable labels. macOS groups native indices by display, so an index
does not have to equal its workspace label: display 1 can contain `2, a` while
display 2 contains `1, 3, 4, …, 9, 0`.

Inspect or repair the order:

```sh
python3 ~/.config/yabai/order-spaces.py --check    # 0 ordered, 1 needs repair, 2 error
python3 ~/.config/yabai/order-spaces.py --dry-run  # show intended order; no changes
python3 ~/.config/yabai/order-spaces.py            # reorder within current monitors
```

From `~/.config`, run the focused regression suite:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s yabai/tests -p 'test_*.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s skhd/tests -p 'test_*.py'
lua sketchybar/tests/workspaces.lua
```

All 44 checks pass: 14 ordering, 6 shortcut-navigation and 24 bar-workspace tests.
Live repair made ten same-display moves while preserving Space IDs, physical
monitor UUIDs, window membership, focused Space and visible Spaces. A second
setup pass made no further moves.

## Services and permissions

```sh
yabai --start-service
skhd --start-service
```

Both binaries require Accessibility permission. Window animations also require
yabai in Screen & System Audio Recording. Keep “Displays have separate Spaces”
enabled and automatic Space rearrangement disabled in Mission Control settings.
Keep “Show Items” → “On Desktop” enabled too: hiding desktop items prevents
yabai from focusing an empty monitor. `macos-defaults.sh` preserves this setting.

On this Mac's macOS 26.6, released yabai 7.1.25 cannot create Spaces. The installed
official source build `HEAD-dd84572` includes the upstream fix for
[issue #2799](https://github.com/asmvik/yabai/issues/2799).
Keep this build until a release includes that fix.

After a yabai upgrade, refresh its hash-pinned sudoers entry:

```sh
sudo bash ~/.config/yabai/setup-scripting-addition.sh --refresh
yabai --restart-service
```

This validates the sudoers file before installing it, authorizes only
`/opt/homebrew/bin/yabai --load-sa`, and refreshes the injected payload.
It briefly restarts the Dock. A changed binary may need its macOS privacy
permissions granted again. Configuration reload is Option+Control+Shift+R.

## Restore the previous window manager

The original configuration archive and AeroSpace checksum are in
`~/.config-backups/before-yabai-20261024-234801/`.
To switch back, stop yabai/skhd, reinstall AeroSpace, restore the SketchyBar files
and AeroSpace configuration from that archive, and launch AeroSpace.
Stopping yabai doesn't remove native Spaces or close your applications.
