# SketchyBar regression tests

From the `.config` directory:

```sh
lua sketchybar/tests/bar.lua
lua sketchybar/tests/workspaces.lua
lua sketchybar/tests/wifi.lua
lua sketchybar/tests/bluetooth.lua
lua sketchybar/tests/bluetooth_controls.lua
lua sketchybar/tests/calendar.lua
lua sketchybar/tests/volume.lua
lua sketchybar/tests/display.lua
python3 -m unittest discover -s sketchybar/tests -p 'test_display_control.py'
lua sketchybar/tests/battery.lua
lua sketchybar/tests/panel.lua
lua sketchybar/tests/network_controls.lua
lua sketchybar/tests/network_panel.lua
lua sketchybar/tests/popup.lua
bash sketchybar/tests/native/run.sh
```

Each test file can also be invoked by absolute path. SketchyBar execution, events,
and time are mocked; the tests do not launch system commands or change hardware.
The native runner builds the local `~/dev/SketchyBar` and `~/dev/SbarLua` sources
in a temporary directory with AddressSanitizer/UBSan. It checks allocation-free
hidden drawing and hit tests, popup surface reuse across 1,000 monitor switches,
grid geometry, cursor ownership, and collection of 2,000 completed exec/timer
closures. It does not run hardware actions. Optional arguments override the two
source directories. Build output is retained at the path printed by the runner.

Coverage includes:

- Coalescing workspace event bursts and rejecting stale results.
- Edge-to-edge bar geometry, tinted translucent styling and blur, removal of
  floating groups, opaque popup defaults and a 10px app-to-bar gap in yabai.
- Fixed-width numbered workspaces, occupied/empty colors, per-display active
  layout glyphs, stale-result rejection, and preserved click targets.
- Reading Wi-Fi link/address state while collapsed, with full details on opening.
- Reading Bluetooth power while collapsed, with device inventory on opening.
- Bluetooth address validation and duplicate-device merging; explicit power,
  connect/disconnect and Forget commands; confirmed-action cancellation and
  readback; opt-in discovery; stale scan/action callbacks; read-only fallback;
  reported battery levels and the existing audio-panel shortcut.
- Calendar month navigation, ISO weeks, leap years, DST boundaries, individual
  day cells, adjacent-month/weekend styling, today highlight, and reset.
- Audio slider validation, output selection, shell quoting, and stale-result rejection.
- BetterDisplay display selection, brightness slider/presets, exact UUID targeting,
  single-write readback verification, bounded CLI timeouts, malformed/unsupported
  data, stale callbacks and polling only while the display panel is open.
- Native network counter parsing, interface resets, service-name discovery, DNS
  address validation, exact readback verification, and previous-setting restore.
- Network telemetry start/stop, serialized actions, stale callback rejection,
  custom-DNS cancellation, speed-test results, and persistence failures.
- Compact four-column DNS layout, optional traffic history, and selected-state
  restoration after hover.
- Battery power-source/status/estimate parsing, failures, and stale-result rejection.
- Shared hover/selected/disabled styling, native-spacing-aware dimensions, named
  panel events, pointing-hand cursors only for enabled actions, and single-panel
  lifecycle hooks with transient missing queries.
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
