# Omarchy-style desktop bar and panels

The bar follows the current [Omarchy shell](https://github.com/omacom/omarchy/tree/quattro/shell/plugins/bar):
a continuous Hubbamax strip, 26px high, flush to the top and sides with no
floating groups, outer gaps or rounded bar corners. The dark background is
approximately 70% opaque with a 20px blur for tinted transparency. Its 8px end
insets are internal; yabai reserves the 26px bar height plus a 10px gap before
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
`SwitchAudioSource` utility.

| Bar item | Left click | Other controls |
| --- | --- | --- |
| Date / clock | Month calendar with ISO weeks and an individually highlighted today | Previous / next month, scroll on the clock, Today reset; right click opens Calendar |
| Wi-Fi | Compact live rates, transfer totals, latency and four-column DNS picker | Expandable traffic history and connection details; provider/custom DNS and previous-setting restore; Wi-Fi power; opt-in speed test; Choose network opens Wi-Fi Settings |
| Bluetooth | Radio state and connected devices | Manage devices or right click opens Bluetooth Settings |
| Audio | Volume slider and up to six output devices | Click an output to switch; scroll on bar adjusts volume, Ctrl-scroll uses smaller steps; right click opens Sound Settings |
| Battery | Power source, charging status and time remaining / time to full | Settings button or right click opens Battery Settings |

Opening a panel closes the previous one. Moving the pointer away from the bar
and popup dismisses it. The clock resets to the current month whenever reopened.
Panels attach directly to the bar so there is no hover gap while entering them.
The active bar item stays highlighted. Hovering a control preserves its actual
selected state when the pointer leaves.

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

The running binary is built from the personal
[SketchyBar fork](https://github.com/agrippa1027/SketchyBar), branch
`feat/omarchy-panels`, at `~/dev/SketchyBar`. The launcher at
`~/.local/bin/sketchybar` points to that checkout's `bin/sketchybar`. Keep its
clicked-display patch: it places panels on the monitor receiving the click.
This branch also adds `popup.columns` and child `cell_span` for native grid
layouts. Engine commit `af92dc4` adds `popup.padding` (0–256)
and `popup.gap` (0–128), defaulting to zero for legacy configurations; spacing
also works in single-column panels. These panels require that newer build.

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
