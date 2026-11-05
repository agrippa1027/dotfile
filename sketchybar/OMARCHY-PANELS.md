# Omarchy-style desktop panels on macOS

Updated: 2026-11-05

## Purpose

Bring Omarchy's useful desktop-panel interactions to this macOS setup using
SketchyBar, SbarLua and the existing Hubbamax palette. Extend the personal
SketchyBar fork when its layout capabilities constrain the panels.

This is an incremental implementation covering the calendar, audio, power,
Wi-Fi/network controls and Bluetooth accessories.

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
- Display: per-display brightness through BetterDisplay, display selection,
  slider and presets, current resolution/refresh rate, and native settings links.
- Network: live download/upload rates, traffic graphs, transfer totals,
  router/internet latency, expandable connection details and refresh.
- DNS: Automatic, Cloudflare, Google, Quad9 and custom IPv4/IPv6 addresses;
  discovery of the actual Wi-Fi service name; previous-setting persistence and
  restore; verification after applying changes.
- Network actions: Wi-Fi power control and an opt-in macOS `networkQuality`
  speed test showing download/upload capacity in Mbps.
- Bluetooth: radio power, connected and remembered device sections, explicit
  connect/disconnect, confirmed Forget, opt-in nearby discovery, reported
  batteries and a shortcut to the audio output picker. Pairing uses Settings.
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
  20px blur, 30px height, zero outer margin/offset, square corners and no floating
  group brackets; 8px internal end insets. Popup backgrounds remain opaque.
- Compact 20px workspace slots with 1px spacing, plain numbers and no app icons
  or filled active pills. Occupied numbers are bright, empty numbers half-opacity.
- Each display marks its visible workspace with a square for tiled layouts or a
  triangle for floating layouts. Existing `0`/`a` labels and focus targets remain.
- yabai reserves 30px for the bar plus 10px of top padding before app windows,
  matching the existing 10px window gaps and side/bottom padding.
- Popup layouts, styling, controls and shortcuts are unchanged.

## Strict workspace ordering

Native managed Spaces now follow `1–9, 0, a` within each display while retaining
their current monitor assignments. Reloading or docking preserves those
assignments; `yabai/setup-spaces.sh --arrange` remains the explicit way to restore
numbered Spaces to the largest display. Unnamed desktops remain at the end, and
native fullscreen Spaces are never move sources or destinations.

Option+N/P cycles the same canonical labels across monitors, skipping fullscreen
and unmanaged desktops. Shortcuts, bar clicks and app routing use stable labels.
Native global indices remain grouped by display and need not match the labels.
Mission Control's recent-use rearrangement is disabled, and lifecycle signals
repair later changes. `yabai/runtime/order-spaces --check` and `--dry-run` inspect the
order without changing it; the default invocation repairs it.

All 44 focused checks pass: 14 ordering, 6 navigation and 24 bar-workspace tests.
Live repair preserved Space IDs, physical monitor UUIDs, window membership,
focused Space and visible Spaces; a repeated setup pass made no moves. Commands
and details are in the [yabai workspace notes](../yabai/README.md#strict-space-ordering).

## Native cursor feedback

The fork supports item `cursor=pointer|default`. Shared panel actions request a
pointing hand while enabled, including the audio slider; disabled controls and
read-only content retain the normal cursor. Native window ownership checks
prevent covered panels from overriding another application's cursor. Existing
engine events restore the cursor on hide, close, removal and reload, without a
new polling timer or application activation.

The signed universal cursor build is installed. Its prior binary and build
metadata are preserved in ignored `runtime/sketchybar-before-cursor` and
`runtime/CURSOR_BUILD.json`. Live checks verified the hand, stationary
disable/re-enable, hidden controls, panel close and unchanged app focus. Native
lifecycle/parser tests and the shared Lua control tests pass; the unrelated
bar/calendar size assertions described in the review still need updating.

The cursor follow-up separates window ownership from cursor shape. Background
cursor permission stays active over popup headings and gaps while the native
image switches from hand to arrow, then releases when leaving SketchyBar.
Existing engine events also reconcile a later cursor-image override from
another app. Live checks verified the actual hand and arrow images on controls,
headings and gaps inside all five popups, without a bar query after each move.
Native ownership regressions pass under AddressSanitizer/UBSan.

## Bluetooth controls and remaining parity

The current [Omarchy Bluetooth panel](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/panels/bluetooth/Panel.qml)
groups connected, remembered and discovered devices, and combines radio/device
actions with battery status and keyboard navigation. The macOS panel now follows
that structure using the existing `blueutil` installation and native popup grid.

Bluetooth radio/device mutations run only after explicit clicks. Off and Forget
use confirmations. Targets are validated device addresses, so a reordered list
or a shell-sensitive peripheral name cannot redirect an action. Readback checks
the resulting state; command failures remain visible. Unknown battery levels
are omitted. A profiler fallback provides read-only information when direct
queries are unavailable.

New-device pairing opens macOS Settings because `blueutil`'s PIN and numeric
confirmation callbacks read terminal input. Running those callbacks in a
background bar process would hide the authentication exchange. Scanning is an
explicit finite inquiry, rather than continuous discovery while the popup is
open. Automated Bluetooth tests mock mutations; the later live action checks
are described below.

Multipoint status follow-up: the default IOBluetooth paired-device query reported
connected earbuds as disconnected while macOS's Bluetooth report correctly
listed them as connected. Snapshots now use
`BLUEUTIL_USE_SYSTEM_PROFILER=1 blueutil --paired/--connected --format json`.
Action preflight and verification select the captured address from the same
report-based snapshot, avoiding inconsistent status from the default `--info`
path. Power, discovery and mutation commands retain their original APIs.
This behavior is documented by [blueutil](https://github.com/toy/blueutil#alternative-method).

Live action validation later covered an actual earbuds connect/disconnect cycle.
Device readback now retries bounded snapshots rather than rejecting a lagging
macOS report immediately. The Keychron was a separate case: the Classic backend
returned "Device not connected" while macOS still reported its BLE connection.
Reported BLE accessories now use native Settings controls instead of advertising
unsupported direct disconnect/forget actions. The earbuds connection and audio
output were restored after testing.

| Area | Current coverage | Remaining gap |
| --- | --- | --- |
| Visual language | Continuous bar, compact workspaces, shared framed cards and native cursors | Further reference-based polish and animation |
| Calendar | Month navigation, ISO weeks, today highlight | In-panel keyboard navigation |
| Audio | Master volume and output picker | Per-app mixing |
| Display | BetterDisplay brightness slider/presets, display picker and mode readouts | In-panel mode, refresh-rate, mirroring and arrangement changes |
| Network | Live rates/history, latency, DNS, radio and speed test | Direct scan/join flow |
| Bluetooth | Power, device management, nearby scan and battery readouts | In-panel authenticated pairing and keyboard navigation |
| Power | Source, charging state and estimates | Power-profile switching and display controls |

## Native display helper

The display panel runs `runtime/display-control`, compiled from C, for inventory,
brightness polling and adjustments. It starts no Python interpreter. Build it
with `make -C ~/.config/sketchybar`; the launcher also rebuilds it when its source
changes, before replacing the running Lua process. Building requires Xcode
Command Line Tools, `pkg-config` and `json-c` (`brew install pkg-config json-c`).
The binary statically links json-c and needs no Homebrew JSON library at runtime.

The JSON interface is `display-control snapshot`, `display-control levels`, or
`display-control brightness UUID PERCENT`. Discovery prefers the Homebrew
BetterDisplay CLI, then falls back to the app executable; `BETTERDISPLAY_BIN`
can select an explicit executable for testing. Commands have a 1.2-second cap,
within an eight-second read budget or six-second adjustment budget. Adjustments
validate the connected display UUID and supported range, write once, and verify
the resulting level with up to three reads. Polling remains every ten seconds
only while the panel is open.

Run `make -C sketchybar test` from the repository root for native bridge and
panel regression tests. Python is used only by the bridge test harness.

## Code map

Paths below are relative to the dotfiles repository unless stated otherwise.

| File | Responsibility |
| --- | --- |
| `sketchybar/bar.lua` | Continuous topbar geometry and background |
| `sketchybar/items/workspaces.lua` | Compact workspace labels, layout/occupancy state and focus targets |
| `sketchybar/items/calendar.lua` | Clock and calendar popup |
| `sketchybar/lib/calendar.lua` | Month and ISO-week calculations |
| `sketchybar/items/widgets/volume.lua` | Audio controls and output picker |
| `sketchybar/items/widgets/display.lua` | Display picker, brightness controls and popup lifecycle |
| `sketchybar/helpers/display_control.c` | Native BetterDisplay CLI bridge and exact-UUID readback verification |
| `sketchybar/items/widgets/wifi.lua` | Wi-Fi status reader and panel integration |
| `sketchybar/items/widgets/network_panel.lua` | Network UI, telemetry and actions |
| `sketchybar/lib/network_controls.lua` | Counter parsing, rates, DNS validation and command construction |
| `sketchybar/items/widgets/bluetooth.lua` | Bluetooth popup, lifecycle and explicit device actions |
| `sketchybar/lib/bluetooth_controls.lua` | Bluetooth address validation, command construction and device models |
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

- Wi-Fi scanning/joining and authenticated Bluetooth pairing still open macOS
  settings. Bluetooth nearby discovery is available directly in the panel.
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
