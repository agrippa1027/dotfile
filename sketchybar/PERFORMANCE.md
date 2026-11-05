# Popup performance

The November 5, 2026 changes are installed in the running top bar. They keep
the existing Omarchy-inspired appearance and native C/Lua implementation.

## Changes

- Popup open, close and selection use the shared lifecycle's local state.
  Synchronous native queries previously interrupted SbarLua's transaction,
  exposing intermediate frames and making unrelated mouse-exit handlers query
  every panel. Inactive close handlers now do no work. Audio callbacks and the
  clock use the same state.
- Shared controls skip unchanged hover, selection and enabled states. Repeated
  resets no longer reapply all control properties.
- The calendar redraws its month grid only when the viewed month or current
  date changes. Navigation and midnight still update the grid.
- The display picker keeps its last inventory and selection visible during
  asynchronous refresh instead of clearing the panel each time it opens.
- Native drawing, clipping checks and hit tests look up existing windows
  without creating windows for hidden rows, timers or unused displays. Popup
  ordering also skips windows that have never been shown.
- Popup rows reuse their native window and backing surface when moving between
  monitors. A popup has one target display, so retaining a surface per monitor
  served no purpose. The engine marks transferred rows for redraw and ordering.
- SbarLua releases completed exec and timer callbacks from the Lua registry,
  frees standalone IPC command buffers, removes callback errors from the Lua
  stack and terminates command output before parsing it. The pinned installer
  applies these fixes on future reinstalls.

There are still two persistent bar processes: SketchyBar and its Lua event loop.
No additional daemon, language runtime, animation timer or polling loop was added.
Existing display/network/Bluetooth telemetry still stops when its panel closes.

## Measurements

Measured on this two-monitor Mac running macOS 26.6.2. The before measurement
used the existing running build; the after measurement used the signed rebuilt
engine with the same six-panel open/close workload.

| Measurement | Before | After |
| --- | ---: | ---: |
| Native windows after the six-panel workload | 392 | 147 |
| SketchyBar physical footprint after workload | 103.5 MB | 61.8 MB |
| Lua physical footprint | 4,225 KB | 3,745 KB |

After opening and hovering all six panels on **both** monitors, the engine held
150 windows and its physical footprint was 61.5 MB. Popup row windows were reused
between displays. Both persistent processes reported 0.0% CPU in the final idle
snapshot.

The physical footprint is the value reported by macOS `sample`, not RSS.
It varies with system caches and visible content. This is an observed workload
comparison, not a fixed memory cap.

Three opens per panel, median elapsed milliseconds:

| Panel | Before | After |
| --- | ---: | ---: |
| Calendar | 78.36 | 47.70 |
| Audio | 63.65 | 36.64 |
| Display | 38.86 | 26.89 |
| Network | 62.77 | 52.30 |
| Bluetooth | 79.29 | 41.98 |
| Power | 58.96 | 33.41 |

These timings include launching the CLI, sending the toggle and reading back
`popup.drawing`. They do not measure compositor presentation or animation frame
rate. This is a small local sample. The first visit to a never-opened panel can
take longer because its windows are allocated on demand; later visits reuse
them. Hardware status continues to arrive asynchronously.

## Verification and reproducibility

- All 208 Lua and 17 display-helper tests pass.
- The [native sanitizer runner](tests/native/run.sh) passes with ASan/UBSan:
  hidden drawing and sparse display hit tests, 1,000 popup surface transfers,
  grid geometry including 8,192 comparisons, cursor ownership, and garbage
  collection of 2,000 completed exec/timer closures.
- Both arm64 and x86_64 engine builds pass; the universal executable is ad-hoc
  signed and passes strict signature verification. The bridge is arm64 for the
  installed Lua 5.5 ABI.
- The engine patch applies cleanly to a preserved copy of the previous source.
  Formatting, changed shell scripts and native runtime loading pass.
- Live checks pass for all six panels on both monitors: native clicks, placement,
  hand/arrow transitions and dismissal. Foreground application focus is preserved.

Native patches are tracked in [patches/](patches/). The engine source changes
are also applied in `~/dev/SketchyBar`; bridge changes are in `~/dev/SbarLua`.
Existing desktop changes in those checkouts were preserved. No package
installations were required.

Ignored local evidence lives in `runtime/PERFORMANCE_BUILD.json`,
`runtime/performance-before.json`, `runtime/performance-after.json` and the
`runtime/performance-*.sample` files. Build metadata records source revisions,
patch hashes and installed binary hashes. The temporary build and live check
scripts remain in `/private/tmp/topbar-performance` for inspection.

The previous binaries are retained as `runtime/sketchybar-before-performance`
and `runtime/sketchybar-before-performance.so`. To revert the entire pass,
restore the pre-pass Lua sources as well as both binaries; native-only rollback
does not revert the Lua caching/lifecycle changes. Copies of those Lua sources
are retained in `runtime/performance-before`. Restart the launch agent after
changing the engine executable; `sketchybar --reload` only reloads configuration.
