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
grids. It builds on `fix/popup-clicked-display`, preserving the custom fix that
opens a panel on the monitor receiving the click. The fork's `master` was
fast-forwarded to upstream commit `a18fc94` during this work.

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

## Code map

Paths below are relative to the dotfiles repository unless stated otherwise.

| File | Responsibility |
| --- | --- |
| `sketchybar/items/calendar.lua` | Clock and calendar popup |
| `sketchybar/lib/calendar.lua` | Month and ISO-week calculations |
| `sketchybar/items/widgets/volume.lua` | Audio controls and output picker |
| `sketchybar/items/widgets/wifi.lua` | Wi-Fi status reader and panel integration |
| `sketchybar/items/widgets/network_panel.lua` | Network UI, telemetry and actions |
| `sketchybar/lib/network_controls.lua` | Counter parsing, rates, DNS validation and command construction |
| `sketchybar/lib/popup.lua` | Shared open/close lifecycle |
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

- All 131 Lua regression tests pass; commands are in [tests/README.md](tests/README.md).
- Native grid tests pass normally and under AddressSanitizer/UBSan.
- Both architecture builds, universal signing, Lua syntax and formatting pass.
- Static analysis retains nine pre-existing warnings; none were added.
- Live checks verified rates, latency, grid layout, expanded details, telemetry
  stopping on close and placement on both monitors.
- A live DNS action reapplied the already-active Cloudflare configuration and
  verified that all four original addresses remained unchanged.
- Actual radio toggling and the bandwidth-consuming speed test were not run;
  their action and result handling were verified with mocks.
- The popup close-event path was verified. Synthetic pointer tests did not
  establish native physical hover-exit delivery.

Review also caught and fixed malformed compressed IPv6 acceptance and a DNS
readback/reopen race that could temporarily block later actions.

## Remaining work and limits

- Wi-Fi scanning/joining and Bluetooth pairing still open macOS settings.
  Direct discovery, credential entry and pairing are future integration work.
- macOS can redact the connected Wi-Fi name.
- Per-app audio mixing, richer display/power panels, keyboard navigation and
  Quickshell-style animations are not implemented.
- Selecting a DNS provider changes the Wi-Fi service's standard DNS settings;
  it does not enable encrypted DNS. VPN/managed profiles may override them.
- Traffic totals are interface counters since their last reset. Graphs use a
  fixed 10 MiB/s scale; higher peaks clip, while numeric rates remain uncapped.
- Grid bracket decorations should stay within one row. Background images do
  not establish a minimum grid size.

Keep further panel work on the feature branches, retain the clicked-display
fix, and add focused regressions when extending layout or network actions.
See [README.md](README.md) for the user-facing controls and provider references.
