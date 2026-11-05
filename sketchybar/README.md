# Omarchy-style desktop bar and panels

The bar follows the current [Omarchy shell](https://github.com/omacom/omarchy/tree/quattro/shell/plugins/bar):
a continuous Hubbamax strip, 30px high, flush to the top and sides with no
floating groups, outer gaps or rounded bar corners. The dark background is
approximately 70% opaque with a 20px blur for tinted transparency. Its 8px end
insets are internal; yabai reserves the 30px bar height plus a 10px gap before
tiled windows. Popup panels remain opaque.

Workspaces use 20px slots separated by 1px, without app icons or filled pills.
Occupied numbers use the normal foreground; empty numbers are half-opacity.
The visible workspace on each display replaces its number with a square (or a
triangle for a floating layout). Existing workspace names, display assignments
and click/keyboard focus behavior are preserved, including `0` and `a`.

Omarchy-inspired panels use the existing SketchyBar Lua runtime and Hubbamax palette.
The current [Omarchy shell](https://github.com/omacom/omarchy/tree/quattro/shell)
is the reference: opaque dark cards, mint 2px frames, compact 4px corners,
monospace title/body/caption hierarchy, and subtle hover/selected controls.
Panels have native 14px insets and 6px row/column gaps.
No additional packages are required; audio output selection uses the installed
`SwitchAudioSource` utility; Bluetooth controls use the installed `blueutil`.
The display panel uses the already-installed BetterDisplay app and CLI.

| Bar item | Left click | Other controls |
| --- | --- | --- |
| Date / clock | Month calendar with ISO weeks and an individually highlighted today | Previous / next month, scroll on the clock, Today reset; right click opens Calendar |
| Wi-Fi | Compact live rates, transfer totals, latency and four-column DNS picker | Expandable traffic history and connection details; provider/custom DNS and previous-setting restore; Wi-Fi power; opt-in speed test; Choose network opens Wi-Fi Settings |
| Bluetooth | Power, connected/remembered devices and nearby discovery | Connect/disconnect, confirmed Forget, opt-in scan, pairing in Settings, and Audio outputs shortcut |
| Audio | Volume slider and up to six output devices | Click an output to switch; scroll on bar adjusts volume, Ctrl-scroll uses smaller steps; right click opens Sound Settings |
| Display | Display picker, brightness slider and 25/50/75/100% presets | Resolution/refresh-rate readouts; BetterDisplay shortcut; right click opens Display Settings |
| Battery | Power source, charging status and time remaining / time to full | Settings button or right click opens Battery Settings |

Opening a panel closes the previous one. Moving the pointer away from the bar
and popup dismisses it. The clock resets to the current month whenever reopened.
Panels attach directly to the bar so there is no hover gap while entering them.
The active bar item stays highlighted. Hovering a control preserves its actual
selected state when the pointer leaves. Enabled controls, including the volume
slider, show a pointing hand; headings, readouts and disabled controls keep the
normal cursor. The cursor returns to normal when a control is hidden or its
panel closes.

### Keyboard shortcuts

Command substitutes for Omarchy's Super key:

| Shortcut | Panel |
| --- | --- |
| `⌘ Ctrl A` | Audio |
| `⌘ Ctrl N` | Network |
| `⌘ Ctrl B` | Bluetooth |
| `⌘ Ctrl P` | Power |
| `⌘ Ctrl Option D` | Calendar |
| `⌘ Ctrl Escape` | Close the active panel |

Repeat a panel shortcut to close it. These are defined in `../skhd/skhdrc`.
Plain Escape, arrows and Tab are not intercepted; in-panel keyboard navigation
and outside-click dismissal are not implemented. Pointer-exit dismissal is
retained from the existing configuration.

### Bluetooth controls

The panel separates connected accessories, remembered devices and nearby scan
results. Connect and Disconnect are explicit buttons. Forget and switching
Bluetooth off require confirmation; opening the panel changes no device state.
Scan nearby runs only when clicked. Pair in Settings uses macOS's visible PIN
and passkey confirmation flow. Audio outputs opens the existing audio panel.

Battery levels appear only when macOS reports them. Device lists are bounded
to keep the popup on screen; additional devices remain available in Settings.
Bluetooth LE accessories such as the Keychron use **Settings ↗** for device
management: the installed Classic Bluetooth backend cannot reliably disconnect
them. Their connection state remains visible in the panel.
Failed commands and unverified changes appear in the panel. Read-only device
information remains available when direct controls cannot be used.
Connection snapshots and action verification use `blueutil`'s macOS report
reader, which handles multipoint earbuds that the default Bluetooth API can
incorrectly mark disconnected. Device actions still target validated addresses.
Device refresh runs every ten seconds while open and stops on close; the bar
keeps its lightweight sixty-second power check. An in-flight scan can finish
after closing, but its results are discarded.

### Display controls through BetterDisplay

Click the monitor icon to select a display and adjust its brightness using the
slider or presets. On first opening, it selects the display under the pointer.
Reopening keeps the selected display visible while fresh data arrives. It shows
up to six displays, their current resolution and refresh rate, and refreshes
brightness every ten seconds while open. Mode details are read on open, manual
refresh, wake and display changes. Closing it stops polling; opening it changes no
display settings. BetterDisplay must be running with command-line integration
enabled. Both the installed CLI and the app-bundle CLI are supported.
The integration follows BetterDisplay's [official CLI reference](https://betterdisplay.pro/guide/integration/cli-reference/).

Actions capture a display's UUID, check that it is still present, apply the
brightness change once and verify the reported level. Names and list positions
are never used as mutation targets. Unknown brightness disables its controls;
unavailable data and failures leave BetterDisplay and right-click Display Settings
available. Each helper invocation has a bounded execution time. Successful
readback updates the slider directly without another full inventory query.

This first display increment covers normal 0–100% brightness. BetterDisplay
selects its configured hardware/software method. A brightness range beyond that
scale is left to BetterDisplay. Resolution changes, refresh-rate changes,
mirroring, arrangement and display disconnection remain in BetterDisplay or
System Settings. Some advanced BetterDisplay controls require Pro.

Live verification changed only the MSI monitor from 50% to 52% through the
slider, then restored 50% through its preset. The built-in display stayed at
98.8%. No display topology or mode changes were made.

The running binary is built from the personal
[SketchyBar fork](https://github.com/agrippa1027/SketchyBar), branch
`feat/omarchy-panels`, at `~/dev/SketchyBar`. The launcher at
`~/.local/bin/sketchybar` points to that checkout's `bin/sketchybar`. Keep its
clicked-display patch: it places panels on the monitor receiving the click.
This branch also adds `popup.columns` and child `cell_span` for native grid
layouts. Engine commit `af92dc4` adds `popup.padding` (0–256)
and `popup.gap` (0–128), defaulting to zero for legacy configurations; spacing
also works in single-column panels. These panels require that newer build.
The fork additionally supports per-item `cursor=pointer|default`; shared panel
controls use this to advertise actions without changing application focus.

The [popup performance changes](PERFORMANCE.md) avoid hidden native windows,
reuse popup row surfaces between monitors, release completed Lua callbacks,
and keep open/close drawing in one transaction. The installed C/Lua stack and
existing visual style are retained.

The rebuilt universal binary is installed and the launch agent restarted.
The previous executable is preserved in ignored `runtime/sketchybar-before-spacing`;
current build/patch metadata is in `runtime/SKETCHYBAR_BUILD.json`.

Traffic is sampled every two seconds while the network panel is open and stops
when it closes. Counters cover the Wi-Fi interface since its last reset; rates
are current traffic, not a measurement of the connection's maximum speed.
History charts use a fixed 10 MiB/s scale and clip higher peaks; numeric rates
remain uncapped. Router and internet (1.1.1.1) latency are sampled every ten
seconds. A missing ICMP reply does not establish that the internet is offline.

The speed-test button runs macOS `networkQuality` for up to 20 seconds and shows
download/upload capacity in Mbps. It uses internet data and runs only on click.

DNS choices are Automatic (DHCP), Cloudflare, Google and Quad9, plus custom IPv4
or IPv6 addresses. The panel discovers the actual Wi-Fi service name, saves its
previous DNS settings in ignored `runtime/network-dns-previous`, and verifies
every change by reading it back. Restore previous reapplies that saved setting,
including Automatic. These are standard system DNS settings; encrypted DNS is
not enabled by selecting a provider. VPN or managed DNS profiles may override
the Wi-Fi service's settings. macOS permission failures appear in the panel.

Provider addresses follow the official [Cloudflare](https://developers.cloudflare.com/1.1.1.1/ip-addresses/),
[Google](https://developers.google.com/speed/public-dns/docs/using), and
[Quad9](https://quad9.net/service/service-addresses-and-features/) documentation.

Wi-Fi names can be hidden by macOS. Network scanning, joining networks, and
Bluetooth pairing use System Settings in this first pass. Per-app audio mixing,
Quickshell animations, and keyboard navigation are not implemented.

Regression commands and coverage are in [tests/README.md](tests/README.md).
The project scope, implementation map, engine build and remaining work are in
[OMARCHY-PANELS.md](OMARCHY-PANELS.md).
