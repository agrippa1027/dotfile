# Milestone 1: Option-drag tile placement

The first live check reproduced a native bug: after a center swap, dropping a
window at the left edge of its sibling swapped it to the right, even though
the mint preview showed the left side. The desktop was restored after the test.

The installed-version source unconditionally swapped sibling nodes when their
split already matched the requested axis. The fix checks the actual source
side: restore the dragged window to its existing tile if it already belongs
there; otherwise swap. Center drops retain their explicit swap behavior.

## Source and validation

- Fork: [agrippa1027/yabai](https://github.com/agrippa1027/yabai).
- Branch: `fix/directional-tile-drop`.
- Fix: [`92ab4ff`](https://github.com/agrippa1027/yabai/commit/92ab4ff).
- Base: `dd845723416f5fe92af49fad5ebab00369e07edd`, matching the installed
  Homebrew source build and retaining its macOS Spaces fix.
- Native regression fails before the fix and passes afterward. Tests exercise
  40 repeated sibling placements across both axes, center swaps, and all five
  pointer drop zones at positive and negative display coordinates.
- All five native tests pass normally and under AddressSanitizer/UBSan.
- Release binary builds for arm64 and x86_64 and passes strict ad-hoc signature
  verification with identifier `com.asmvik.yabai`.

Installation refreshes the hash-pinned scripting-addition authorization using
the existing `setup-scripting-addition.sh`; its payload protocol is unchanged.
macOS requires reauthorizing Accessibility for the new ad-hoc signature before
the daemon can start. Accessibility was reauthorized, the service restarted,
and the fixed build is now running. Ten live drags pass: center swaps, all four
edges, and starts from both title bars and window bodies. Native insertion
indicators appear during dragging and disappear after release; ordinary clicks
still focus windows. Original frames, Space assignments, focused window and
pointer position were restored after the test.

Ignored `runtime/M1_BUILD.json` records activation, binary hashes and verification;
`runtime/m1-live-before.json` and `runtime/m1-live-after.json` retain the local
evidence. The installed binary matches the tested candidate's SHA-256 hash.

The service restart also exposed a separate setup limitation: yabai's Space
labels are held in daemon memory, and startup assigned them afresh. All 15
original Space identities, their original labels and monitor assignments,
visible Spaces and real-window membership were restored and verified afterward.
Six empty Spaces created by that startup were removed. The restoration record
is in `runtime/m1-space-restored.json`. Future daemon replacements must snapshot
and restore the label-to-Space mapping; config reload alone does not lose it.

## Repeat the live check

```sh
python3 ~/.config/yabai/tests/check_drag.py --live
```

Without `--live`, the script only prints usage. With it, the script compiles and
opens three disposable standard AppKit windows and posts real Option-drag
events. It checks center swaps, four edge placements, title-bar/body dragging,
native preview creation/removal and ordinary clicks. It then closes its own
windows, restores the pointer and original focused window, and verifies the
original window frames and Space assignments. Reports and screenshots are
retained in the printed `/private/tmp/wm-drag-check-*` directory.

The check temporarily tiles its windows beside the existing app. Run it when
you are not using the pointer. It does not edit documents, create/delete Spaces,
or change persistent window-manager settings.

## Build and rollback records

The source checkout is `~/dev/yabai`; the active installation remains at the
existing Homebrew path behind `/opt/homebrew/bin/yabai`. A later Homebrew
upgrade can replace this custom binary.

Ignored `runtime/` retains the previous executable as `yabai-before-m1`, its
previous sudoers rule as `yabai-sudoers-before-m1`, native test logs and build
hashes. Restoring both files and restarting the service reverts the native
change. The sudoers file requires administrator access and must retain root
ownership and mode `0440`.
