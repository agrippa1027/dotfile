# Hubbamax yabai desktop

The desktop uses yabai for native macOS Spaces, skhd for global shortcuts,
and SketchyBar for the edge-to-edge Omarchy-style status bar. JankyBorders has been removed.
The AeroSpace app was uninstalled; `~/.config/aerospace/aerospace.toml` remains
unchanged from the start of this migration.

## Appearance and workspaces

- 10px window gaps and padding on every side; 26px reserved for SketchyBar
  plus 10px of top padding between the bar and app windows.
- Tinted translucent Hubbamax bar, compact numbered Spaces, a square for each display's
  visible tiled Space (triangle for floating), and dimmed empty Spaces.
- Focused windows: 100% opacity; inactive: 96%, transitioning over 0.15 seconds.
  Firefox and video players (IINA, Stremio, VLC, mpv, QuickTime Player) stay at
  100% opacity even when unfocused, so video content does not become transparent.
- Window move/resize animations are disabled to avoid a CoreVideo display-link
  deadlock observed after sleep/display reconfiguration.
- Shadows on floating windows; tiled windows have no shadows.
- Numbered Spaces 1–9 and 0 start on the largest display; Space a starts on the other
  display. Existing labeled Spaces retain their current locations when reloaded.
  Connecting a display reconciles this arrangement automatically; it can also be
  restored with `~/.config/yabai/setup-spaces.sh --arrange`.
- Firefox/Chrome → 1, Zed → 2, Obsidian → 3, calibre → 4, Bruno → 6,
  Discord → 7, regular Ghostty terminals → 9 (and follow focus). The scratchpad
  remains separate. Finder, settings, messaging, and utility dialogs float.

Internal labels use `ws-1` through `ws-9`, `ws-0`, and `ws-a` because yabai rejects
purely numeric labels. The bar and shortcuts translate these to their short names.
Command+A stays Select All; Option+A focuses Space a.

See [the shortcut reference](../skhd/README.md). Option+K opens it.

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
from that archive, and launch AeroSpace. Its original config is already preserved.
Stopping yabai doesn't remove native Spaces or close your applications.
