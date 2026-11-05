# Yabai performance audit — 2026-11-05

The running milestone 1 build is already small and idle-efficient. A focused
native memory-lifetime fix is prepared in the personal fork; it is not installed.

## Measurements from the running build

MacOS 26.6.2, two monitors, two tracked app windows, 15 Spaces. Running source:
`92ab4ff`, including the directional tile-drop correction.

| Check | Observed result |
| --- | --- |
| Idle CPU snapshot | 0.0%; event and socket threads blocked waiting for work |
| Physical footprint during the query workload | 9,553,472 bytes, approximately 9.55 MB |
| Read-only workload | 100 Space queries and 100 window queries over the native socket |
| Workload wall time | 600.206 ms |
| Yabai CPU time for that workload | 4.408 ms |
| Median Space query reply | 3.436 ms |
| Median window query reply | 1.363 ms |
| Footprint before, immediately after, and after settling | Identical in all three samples |
| Process peak reported by macOS | 54.4 MB since launch; not attributed to a particular operation |

The footprint comes from macOS process resource accounting and was cross-checked
with `sample`/`vmmap`. Large mapped framework and reserved-memory totals are not
equivalent to private physical memory. The 8 MB temporary arena should not be
reduced just to make the virtual-memory number smaller.

This is one local sample with a small window count. The query workload is
read-only; it does not establish animation frame rate or performance with many
apps. It also does not exercise the fallback-discovery leak described below.

## Confirmed fix: rejected Accessibility probes were retained

Fallback discovery probes up to 32,767 remote Accessibility element IDs when
the normal app/window lists disagree. The original code released a rejected
probe only when its role was a window. Candidates with an absent role or a
non-window role leaked their owned reference.

`src/ax_window_probe.h` now owns that decision in one place. Rejected probes
are released; successful matches transfer their ownership to the existing
window object. A null candidate is handled without an invalid AX request.
The original window-ID matching and discovery limit are retained.

The same pass releases the owned result of the private `__fence` attribute read
when one is returned during app switching.

Validation:

- 32,771 controlled probe cases pass under AddressSanitizer/UBSan, including
  a maximum-length absent-role scan, null creation, non-window roles, unknown
  IDs and successful ownership transfer. No probe references remain after
  the adopting owner releases its successful result.
- All five existing native tests pass normally and under ASan/UBSan, retaining
  milestone 1's drag regressions.
- The production candidate builds for arm64 and x86_64 and passes strict
  ad-hoc signature verification.
- Upstream's `window_manager.c` blob at audit time matched the pre-fix base
  (`13bc2458a9be0c579f8688f4ed294e0aaa213fab`); the change is not a duplicate
  of a newer implementation of this file.

These are ownership and build results, not a measured before/after reduction
in the live daemon's memory. The expected benefit is preventing growth during
fallback discovery; a large reduction from the current idle footprint is not
established.

## Other performance findings

1. **Manual resizing:** the current handler has a 67.67 ms minimum update
   interval, roughly a 15-update/s ceiling. Its elapsed-time expression also
   casts the absolute nanosecond timestamp to `float` before subtraction.
   Frame pacing and timestamp precision are concrete targets for milestone 2.
2. **Event-loop burst handling:** an isolated run through the production event
   loop processed 4,000 dummy events with 4,001 semaphore-wait calls and about
   1.387 ms of CPU. It drains the event queue before consuming the remaining
   semaphore tokens. There is redundant work, but this sample does not justify
   changing its concurrency protocol ahead of the memory fix and resize work.
3. **Workspace hooks:** geometry changes can spawn a shell and bar refresh via
   the configured `window_moved` signal. Any future coalescing must preserve
   workspace occupancy updates, especially moves without following focus.
4. **Leak scanner:** the live scan reported about 14 KB of unreachable objects,
   predominantly XPC/KVO framework objects. That is not evidence that the live
   daemon is presently accumulating megabytes of the fallback probes.

## Source, tests and activation

Source checkout: `~/dev/yabai`; personal fork:
[agrippa1027/yabai](https://github.com/agrippa1027/yabai), branch
[`perf/resource-lifetime`](https://github.com/agrippa1027/yabai/tree/perf/resource-lifetime).
The tested native fix is committed as
[`3355fe1`](https://github.com/agrippa1027/yabai/commit/3355fe1).

```sh
make -C ~/dev/yabai/tests build run
make -C ~/dev/yabai/tests memory
```

The memory target uses synthetic AX responses and real CoreFoundation ownership;
it does not inspect apps or move windows. Local profiles, hashes, workload
results and logs are preserved under ignored `yabai/runtime/performance/`.
The temporary candidate and isolated event-loop benchmark are in
`/private/tmp/yabai-performance/`.

The running binary remains the verified milestone 1 build. Activating this
candidate would change its ad-hoc signature and pinned loader hash. Preserve
and restore native Space labels across the daemon restart, and account for
macOS Accessibility reauthorization, as established during milestone 1.
