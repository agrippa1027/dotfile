# Desktop panels

Omarchy-inspired panels using the existing SketchyBar Lua runtime and Hubbamax palette.
No additional packages are required; audio output selection uses the installed
`SwitchAudioSource` utility.

| Bar item | Left click | Other controls |
| --- | --- | --- |
| Date / clock | Month calendar with ISO weeks and today marked in brackets | Previous / next month, scroll on the clock, Today reset; right click opens Calendar |
| Wi-Fi | Live traffic graphs, transfer totals, latency, DNS controls and connection details | Provider/custom DNS and previous-setting restore; Wi-Fi power; opt-in internet speed test; Choose network opens Wi-Fi Settings |
| Bluetooth | Radio state and connected devices | Manage devices or right click opens Bluetooth Settings |
| Audio | Volume slider and up to six output devices | Click an output to switch; scroll on bar adjusts volume, Ctrl-scroll uses smaller steps; right click opens Sound Settings |
| Battery | Time remaining | Right click opens Battery Settings |

Opening a panel closes the previous one. Moving the pointer away from the bar
and popup dismisses it. The clock resets to the current month whenever reopened.
Panels attach directly to the bar so there is no hover gap while entering them.

The running binary is built from the personal
[SketchyBar fork](https://github.com/agrippa1027/SketchyBar), branch
`feat/omarchy-panels`, at `~/dev/SketchyBar`. The launcher at
`~/.local/bin/sketchybar` points to that checkout's `bin/sketchybar`. Keep its
clicked-display patch: it places panels on the monitor receiving the click.
This branch also adds `popup.columns` and child `cell_span` for native grid
layouts. The expanded network panel requires that build.

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
