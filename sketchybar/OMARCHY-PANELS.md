# Omarchy-style desktop panels on macOS

Updated: 2026-11-04

## Purpose

Bring Omarchy's useful desktop-panel interactions to this macOS setup using
SketchyBar, SbarLua and the existing Hubbamax palette. Extend the personal
SketchyBar fork when its layout capabilities constrain the panels.

This is an incremental implementation. The current focus is the calendar,
audio controls and a richer Wi-Fi/network panel.

## Repositories and branches

| Repository | Location | Feature branch |
| --- | --- | --- |
| [Dotfiles](https://github.com/agrippa1027/dotfile) | `~/.config` | `feat/omarchy-panels` |
| [SketchyBar fork](https://github.com/agrippa1027/SketchyBar) | `~/dev/SketchyBar` | `feat/omarchy-panels` |

Dotfiles `main` preserves the earlier configuration work. Commit `b6e0231`
records the user's pre-existing tmux session-chooser and Zed ask-profile changes.
The panel work branches from that commit; it has not been merged into `main`.

The engine feature branch contains commit `f298ce5`, which adds native popup
grids, and `af92dc4`, which adds native popup padding and gaps. It builds on
`fix/popup-clicked-display`, preserving the custom fix that opens a panel on
the monitor receiving the click. The fork's `master` was fast-forwarded to
upstream commit `a18fc94` during this work.

## Implemented

- Calendar: Monday-first month grid, ISO week numbers, previous/next month,
  scroll navigation, today reset and a native Calendar shortcut.
- Audio: volume slider, active-output indication and output-device selection
  through the existing `SwitchAudioSource` installation.
- Network: live download/upload rates, traffic graphs, transfer totals,
  router/internet latency, expandable connection details and refresh.
- DNS: Automatic, Cloudflare, Google, Quad9 and custom IPv4/IPv6 addresses;
  discovery of the actual Wi-Fi service name; previous-setting persistence and
  restore; verification after applying changes.
- Network actions: Wi-Fi power control and an opt-in macOS `networkQuality`
  speed test showing download/upload capacity in Mbps.
- Shared behavior: one open panel at a time, close hooks to stop telemetry,
  consistent styling and safe handling of incomplete startup queries.
- Engine: `popup.columns` and per-item `cell_span` support compact native grids
  with wrapping, full-width headings, variable row heights and hidden items.
  Existing one-column horizontal/vertical layouts keep their previous path.

Traffic samples run every two seconds and latency probes every ten seconds
while the network panel is open. Closing it stops periodic telemetry. Opening
or refreshing a panel does not change DNS, toggle Wi-Fi or start a speed test.

## Visual refinement pass

The reference is the current [Omarchy Quickshell source](https://github.com/omacom/omarchy/tree/quattro/shell),
particularly `Commons/Style.qml`, `Ui/KeyboardPanel.qml` and the network panel,
not an older Waybar theme. Hubbamax and the existing monospace font remain.

- Shared cards: opaque background, 2px mint frame, 4px corners, native 14px
  insets and 6px gaps, with 14/12/10px title/body/caption hierarchy.
- Controls: quiet borders, separate hover/current states, and an active bar-item
  background. Hovering does not lose the real DNS/output selection.
- Network: connection header, compact aligned metrics, one four-choice DNS row,
  and optional traffic-history/details expansions instead of graph-led content.
- Calendar: native eight-column ISO-week/day grid, individual today highlight,
  subdued weekends and adjacent-month dates, compact month navigation.
- Audio/Bluetooth/power: consistent section styling and controls; power now
  distinguishes source, charging/full/paused state and appropriate estimates.
- Invocation: `Cmd+Ctrl+A/N/B/P` for audio/network/Bluetooth/power,
  `Cmd+Ctrl+Option+D` for calendar, `Cmd+Ctrl+Escape` to close. Repeat to toggle.
  App keys are not captured for in-panel navigation.
- Engine: `popup.padding` (0–256) and `popup.gap` (0–128), strict integer
  validation and query support. Defaults remain zero; nonzero spacing enables
  grid geometry even for one-column panels. Spans include internal gaps.

These refinements are recorded on the existing `feat/omarchy-panels` branches.
The new signed universal executable is installed. The previous executable is preserved
at `sketchybar/runtime/sketchybar-before-spacing`; current build and patch
metadata are in `sketchybar/runtime/SKETCHYBAR_BUILD.json`.

## Edge-to-edge topbar pass

The topbar now follows the current Omarchy shell's
[`Bar.qml`](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/bar/Bar.qml)
and [`Workspaces.qml`](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/bar/widgets/Workspaces.qml):

- Continuous dark-tinted Hubbamax background at approximately 70% opacity with
  20px blur, 26px height, zero outer margin/offset, square corners and no floating
  group brackets; 8px internal end insets. Popup backgrounds remain opaque.
- Compact 20px workspace slots with 1px spacing, plain numbers and no app icons
  or filled active pills. Occupied numbers are bright, empty numbers half-opacity.
- Each display marks its visible workspace with a square for tiled layouts or a
  triangle for floating layouts. Existing `0`/`a` labels and focus targets remain.
- yabai reserves 26px for the bar plus 10px of top padding before app windows,
  matching the existing 10px window gaps and side/bottom padding.
- Popup layouts, styling, controls and shortcuts are unchanged.

## Code map

Paths below are relative to the dotfiles repository unless stated otherwise.

| File | Responsibility |
| --- | --- |
| `sketchybar/bar.lua` | Continuous topbar geometry and background |
| `sketchybar/items/workspaces.lua` | Compact workspace labels, layout/occupancy state and focus targets |
| `sketchybar/items/calendar.lua` | Clock and calendar popup |
| `sketchybar/lib/calendar.lua` | Month and ISO-week calculations |
| `sketchybar/items/widgets/volume.lua` | Audio controls and output picker |
| `sketchybar/items/widgets/wifi.lua` | Wi-Fi status reader and panel integration |
| `sketchybar/items/widgets/network_panel.lua` | Network UI, telemetry and actions |
| `sketchybar/lib/network_controls.lua` | Counter parsing, rates, DNS validation and command construction |
| `sketchybar/lib/popup.lua` | Shared open/close lifecycle, named toggles and active-item styling |
| `sketchybar/lib/panel.lua` | Heading/section hierarchy and hover/selected/disabled control styling |
| `sketchybar/items/panel_keys.lua` | Hidden receivers for skhd panel shortcuts |
| `sketchybar/items/widgets/battery.lua` | Power source/status/estimate panel |
| `sketchybar/settings.lua` | Shared dimensions, fonts and settings shortcuts |
| `~/dev/SketchyBar/src/popup_grid.h` | Window-independent grid geometry and integer validation |
| `~/dev/SketchyBar/src/popup.c` | Native popup grid integration |
| `~/dev/SketchyBar/tests/popup_grid.c` | Native geometry regression tests |

## Build and runtime

`~/.local/bin/sketchybar` is a symlink to
`~/dev/SketchyBar/bin/sketchybar`. The existing launch agent is
`~/Library/LaunchAgents/local.sketchybar.plist`, label `local.sketchybar`.
The expanded network panel requires the custom grid-enabled engine build.

The installed binary was rebuilt for arm64 and x86_64, combined into a universal
binary, ad-hoc signed, verified and installed. SbarLua was reused; no packages
were added. Build metadata is local and ignored at
`sketchybar/runtime/SKETCHYBAR_BUILD.json`.

To build both architectures without overwriting the running binary:

```sh
cd ~/dev/SketchyBar
mkdir -p /private/tmp/sketchybar-panel-build
make arm64 ODIR=/private/tmp/sketchybar-panel-build/arm64
make x86 ODIR=/private/tmp/sketchybar-panel-build/x86
lipo -create -output /private/tmp/sketchybar-panel-build/sketchybar \
  /private/tmp/sketchybar-panel-build/arm64/sketchybar \
  /private/tmp/sketchybar-panel-build/x86/sketchybar
codesign --force --sign - /private/tmp/sketchybar-panel-build/sketchybar
codesign --verify --strict /private/tmp/sketchybar-panel-build/sketchybar
```

After verifying a build, preserve the existing binary before replacing it.
Restart the launch agent to load a new executable. `sketchybar --reload` reloads
the Lua configuration; it does not replace the running executable.

DNS restore data lives in ignored `sketchybar/runtime/network-dns-previous`.
Keep it local. Runtime binaries, DNS snapshots and `.omx` state are not part of
the committed feature.

## Verification completed

- Lua regression commands and coverage are in [tests/README.md](tests/README.md),
  including bar geometry, yabai reservation and compact multi-display workspace states.
- Native grid tests pass normally and under AddressSanitizer/UBSan, including
  8,192 zero-spacing comparisons with the original geometry and focused spacing,
  hidden/full-span/single-column/parser tests. An actual-engine offline harness
  checks parsing/query output, layout routing and clicked-display inheritance.
- Both architecture builds, universal signing, Lua syntax and formatting pass.
- The earlier foundation pass retained nine static-analysis warnings. That full
  static-analysis sweep was not repeated for this refinement.
- Live checks verified rates, latency, grid layout, expanded details, telemetry
  stopping on close and placement on both monitors.
- A live DNS action reapplied the already-active Cloudflare configuration and
  verified that all four original addresses remained unchanged.
- Actual radio toggling and the bandwidth-consuming speed test were not run;
  their action and result handling were verified with mocks.
- Live visual checks covered the refined network, calendar, audio, Bluetooth
  and power panels. Switching away from network stops its telemetry. Shortcut
  invocation uses the shared lifecycle; native padding/gap query values match.
- The popup close-event path was verified. Synthetic pointer tests did not
  establish native physical hover-exit delivery.

Review also caught and fixed malformed compressed IPv6 acceptance and a DNS
readback/reopen race that could temporarily block later actions.

## Remaining work and limits

- Wi-Fi scanning/joining and Bluetooth pairing still open macOS settings.
  Direct discovery, credential entry and pairing are future integration work.
- macOS can redact the connected Wi-Fi name.
- Per-app audio mixing, display controls, power-profile switching, in-panel
  arrow/Tab navigation and Quickshell-style animations are not implemented.
- Pointer-exit dismissal remains. Outside-click dismissal and plain Escape
  capture require additional integration; `Cmd+Ctrl+Escape` closes panels without
  taking ordinary application keys.
- Selecting a DNS provider changes the Wi-Fi service's standard DNS settings;
  it does not enable encrypted DNS. VPN/managed profiles may override them.
- Traffic totals are interface counters since their last reset. Graphs use a
  fixed 10 MiB/s scale; higher peaks clip, while numeric rates remain uncapped.
- Grid bracket decorations should stay within one row. Background images do
  not establish a minimum grid size.

Keep further panel work on the feature branches, retain the clicked-display
fix, and add focused regressions when extending layout or network actions.
See [README.md](README.md) for the user-facing controls and provider references.
