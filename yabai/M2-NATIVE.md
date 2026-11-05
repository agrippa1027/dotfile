# Milestone 2: native resize implementation review

The user confirmed the implementation policy: native C inside yabai for
everyday interactions; Python is acceptable for one-time installation,
measurement and test tools. CPU usage and retained memory are requirements.

## What executes while resizing

The active build's `MOUSE_DOWN`, `MOUSE_DRAGGED` and `MOUSE_UP` handlers call the
native functions in `~/dev/yabai/src/mouse_resize.h`. They do not call the
Python installer or measurement script.

- Pacing uses an integer nanosecond delta with a 16 ms update budget, replacing
  the previous 67.67 ms interval and float conversion of absolute timestamps.
- Pacing-rejected events do not perform Accessibility geometry reads/writes.
- Accepted geometry is kept separately from the asynchronous notification
  cache, with bounded readback to handle app size constraints and reversals.
- Mouse release applies the final pointer endpoint without pacing it away.
- The implementation uses the existing event loop and adds no resident helper,
  resize timer or polling thread.
- `struct mouse_state` grows from 136 to 192 bytes on this arm64 Mac: 56 bytes
  of additional retained state for the daemon. This is not a claim that total
  process footprint changes by exactly 56 bytes; code and OS API allocations
  are separate. Copied geometry values are released on success/error paths.

Using C is appropriate here because it uses yabai's existing event and window
state directly, without interpreter startup or cross-process control per event.
Changing the language of a one-time installer would not make this resize path
faster. Live latency, CPU and memory measurements remain the acceptance criteria.

## One-time Python tools

- `activate-resize.py`: explicit installation, startup label restoration and
  rollback. Its default is a read-only preflight. Its authorization-renewal
  thread exists only during the activation transaction.
- `tests/check_resize.py`: opt-in measurement with disposable windows. The
  reported native bounds changes are observations, not compositor frame rates.
- `tests/test_activate_resize.py`: mocked installer regressions.

These tools are not bound to Option-right-drag. No Python resize process was
present in the running process inspection. An existing Space-ordering script
is a separate lifecycle integration, not part of M2's pointer handling.

Review corrected the activation helper's Space-focus command to the native
syntax `yabai -m space --focus DESTINATION`; the test double now rejects the
previous invalid form. A fixture also now records the canonical path expected
by rollback verification on macOS's `/var` symlink.

## Verification and status

- All 24 production resize/BSP/signal regressions pass under ASan/UBSan.
- Existing native regressions and 32,771 ownership cases also pass in that run.
- All 43 mocked activation tests pass, including nearest-pixel pointer restoration.
- Python syntax and whitespace checks pass.
- The recorded pre-M2 live measurements observed about 12.6 bounds changes/s
  on both displays, with p95 intervals around 75 ms and restored desktops.

## Activation and live results

Activated 2026-11-05 from the personal fork's
[`feat/smooth-mouse-resize`](https://github.com/agrippa1027/yabai/tree/feat/smooth-mouse-resize)
branch, commit [`0ec99d5`](https://github.com/agrippa1027/yabai/commit/0ec99d5).
The installed binary matches the tested M2 SHA-256:
`3443cdd1da2da5f1ecbaf029c2a1de8538d2468c2310f8549747951325653440`.

Three live resize gestures on the currently connected display observed:

| Gesture | Bounds changes/s | p95 interval | Last change after release | Daemon CPU |
| --- | ---: | ---: | ---: | ---: |
| Grow 120px | 54.5 | 33.0 ms | 26.5 ms | 0.99 ms |
| Shrink 100px | 58.5 | 25.0 ms | 27.7 ms | 1.12 ms |
| Grow 80px | 56.5 | 16.9 ms | 13.7 ms | 1.02 ms |

All three retained tiling/gaps and had no changes more than 250 ms after release.
The test restored the desktop. Idle physical footprint was approximately
8.37 MB afterward, with approximately 0.0005% CPU over the short idle sample.
This is not a fixed memory cap or an isolated before/after memory reduction.
Bounds changes are observations, not compositor frame-rate measurements.

The earlier baseline observed about 12.6 changes/s. The Mac rebooted between
that baseline and activation, leaving one display connected, so this historical
comparison is indicative rather than a controlled two-display A/B benchmark.
Live verification on the second display remains pending until it is connected.

The reboot occurred before M2 was installed. Recovery reapplied the configured
labels to the 19 existing post-reboot Spaces in their current order without
creating/moving desktops. Activation preserved that recovered topology and the
original app memberships. Its saved transaction is in ignored
`runtime/activation-juzq8ifj`; keep that directory because the loaded launch agent
uses its config wrapper. Its active wrapper invokes the normal shell config,
with no resident Python activation process.

The initial activation Terminal closed during permission setup. Finalization
verified the original document windows and excluded only that known temporary
Terminal from the captured membership check; the initial snapshot remains in
the journal. Cursor restoration now rounds to the nearest pixel before Quartz
warping, preserving the half-pixel verification tolerance.

Evidence: `runtime/m2/live-active.json` and `runtime/m2/BUILD.json`. Backups and
the rollback command are retained in the activation record. Arbitrary later
daemon restarts still need label snapshot/restore; this transaction's early
label guard does not implement general label persistence across reboot.
