# Desktop panels

Omarchy-inspired panels using the existing SketchyBar Lua runtime and Hubbamax palette.
No additional packages are required; audio output selection uses the installed
`SwitchAudioSource` utility.

| Bar item | Left click | Other controls |
| --- | --- | --- |
| Date / clock | Month calendar with ISO weeks and today marked in brackets | Previous / next month, scroll on the clock, Today reset; right click opens Calendar |
| Wi-Fi | Current connection, address, router, and refresh action | Choose network opens macOS Wi-Fi Settings |
| Bluetooth | Radio state and connected devices | Manage devices or right click opens Bluetooth Settings |
| Audio | Volume slider and up to six output devices | Click an output to switch; scroll on bar adjusts volume, Ctrl-scroll uses smaller steps; right click opens Sound Settings |
| Battery | Time remaining | Right click opens Battery Settings |

Opening a panel closes the previous one. Moving the pointer away from the bar
and popup dismisses it. The clock resets to the current month whenever reopened.
Panels attach directly to the bar so there is no hover gap while entering them.

The running binary is built from the personal
[SketchyBar fork](https://github.com/agrippa1027/SketchyBar), branch
`fix/popup-clicked-display`, at `~/dev/SketchyBar`. The launcher at
`~/.local/bin/sketchybar` points to that checkout's `bin/sketchybar`. Keep its
clicked-display patch: it places panels on the monitor receiving the click.

Wi-Fi names can be hidden by macOS. Network scanning, joining networks, and
Bluetooth pairing use System Settings in this first pass. Per-app audio mixing,
Quickshell animations, and keyboard navigation are not implemented.

Regression commands and coverage are in [tests/README.md](tests/README.md).
