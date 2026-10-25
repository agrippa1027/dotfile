# SketchyBar regression tests

From the `.config` directory:

```sh
lua sketchybar/tests/workspaces.lua
lua sketchybar/tests/wifi.lua
lua sketchybar/tests/bluetooth.lua
```

Each test file can also be invoked by absolute path. SketchyBar execution, events,
and time are mocked; the tests do not launch system commands or change hardware.

Coverage includes:

- Coalescing workspace event bursts and rejecting stale results.
- Preserving workspace icons, focus styling, and click targets.
- Reading Wi-Fi link/address state while collapsed, with full details on opening.
- Reading Bluetooth power while collapsed, with device inventory on opening.
- Fallbacks for missing link/power information and failed queries.
- Opening popups during an in-flight refresh without losing the detail request.
- Recovering on a later event after a missing callback, using a 65-second
  per-command watchdog beyond SbarLua's 60-second worker alarm.

The watchdog does not cancel external processes; generation checks reject late
results. It prevents ordinary event bursts from overlapping refreshes, not a
strict process-tree timeout guarantee for hung commands.

Mock command counts do not establish CPU or battery savings. After reloading the
live bar, check workspace highlighting and both network popups. Collapsed Wi-Fi
uses link status and an address; power is verified when opening the popup.
Bluetooth uses macOS's stored power preference, falling back to the profiler if
that preference is missing or invalid.
