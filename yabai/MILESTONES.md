# Window-manager look and feel

Checkpoint: `bdeae9f` on `feat/omarchy-panels`, pushed on 2026-11-05.
The top bar and cleanup are the baseline for this phase.

Work in small increments, each with one visible outcome. Record the behavior,
change, verification and rollback before taking the next checkpoint. Evaluate
the feel with ordinary applications, not just automated tests.

The user authorizes cloning and modifying yabai when it improves this setup.
Fork yabai to the user's GitHub account before making native changes. The
dedicated checkout is `~/dev/yabai`, with origin `agrippa1027/yabai` and
upstream `asmvik/yabai`.
Native fixes are in scope; investigate measured bottlenecks rather than limiting
the work to configuration. Keep a dedicated source checkout and preserve this
Mac's installed Spaces fix when building replacements. Any replacement must
also account for its hash-pinned scripting-addition authorization and existing
macOS permissions. Source work stays within the current milestone.

## 1. Option-drag to rearrange tiles — complete

Completed 2026-11-05. Live testing reproduced a directional-drop bug in yabai:
an already-correct edge placement swapped the window to the opposite side.
The correction is installed from the personal fork at
[`92ab4ff`](https://github.com/agrippa1027/yabai/commit/92ab4ff).
See [the native fix and verification record](M1-DRAG.md).

- Hold **Option**, then left-click and drag a tiled window. The window body or
  a draggable title-bar area works; the body avoids app-specific title-bar controls.
- Drop over the **middle** of another tiled window to swap their positions.
- Drop near its **left, right, top or bottom edge** to insert on that side.
- Release the mouse button before releasing Option.

The existing mint insertion indicator should show the target region during
the drag. Start with two tiled windows on one desktop; a single window has no
other tile to exchange positions with. Floating windows move freely instead.

Done when center swaps and edge insertions are predictable in repeated trials,
the windows remain tiled, gaps are preserved, and normal clicks still work.
Limit initial fixes to dragging and drop targets.

Verified live settings: `mouse_modifier=alt`, `mouse_action1=move`,
`mouse_action2=resize`, `mouse_drop_action=swap`,
`insert_feedback_color=0xff87ffaf`. The native correction passes ten live drops,
including all four edges, center swaps and title-bar/body starts. Preview cleanup
and ordinary clicks pass. The original desktop layout, Space assignments,
pointer and focus were restored. Five native tests also pass under ASan/UBSan.
The existing drag bindings, animation settings and motion preferences were retained.

## 2. Smooth manual resizing — next

One outcome: Option-right-drag resizes tiles responsively, and neighboring tiles
settle correctly on release. Begin by measuring the current behavior.

The installed Homebrew source has a 67.67 ms minimum interval in its drag-resize
path, approximately 15 updates per second. This is a candidate bottleneck to
measure before changing it; it is not a measured frame-rate result. Preserve
the installed source build's Spaces fix if a native change is necessary.

Done when resizing tracks the pointer without a queue of delayed updates,
works on both displays, and returns to the idle resource baseline afterward.

## 3. A smooth tile transition

One outcome: swapping two tiles settles with a short, consistent eased movement.
Use two disposable windows first, then check ordinary apps. Tune duration only
after the animation path is reliable. Check rapid repeated swaps and display
changes; sleep/wake must be included in the verification before calling this done.

Current baseline: window-frame animation duration is zero. The config records
a previous CoreVideo display-link deadlock during sleep/display changes. macOS
Reduce Motion is also enabled. These are separate settings; investigate the
yabai issue before enabling animations persistently or changing global motion
preferences. Opacity currently transitions over 0.15 seconds.

## 4. Clear, calm focus

One outcome: the active window is easy to identify without distracting flicker
or surprising pointer movement. Review the current 100%/96% opacity distinction
and mouse-follows-focus behavior independently. Test keyboard focus, mouse focus
and dialog activation. Add a visual indicator only if the existing cues are
insufficient. Media content should retain its current opaque treatment.

## 5. Moving between displays

One outcome: Option-dragging a tile to another display preserves tiling and
leaves focus and the pointer in sensible places. Verify both directions,
different display sizes, and removal/reconnection of the external display.
Keep existing workspace labels, window membership and monitor assignments.

Native Space transitions are a separate follow-up. Treat their achievable
animation behavior as a macOS constraint to investigate, not a promise of
Hyprland-equivalent compositor effects.

## References

- [Omarchy's mouse bindings](https://github.com/omacom/omarchy/blob/quattro/default/hypr/bindings/tiling.lua): Super-left-drag moves; Super-right-drag resizes.
- [Omarchy look and feel](https://github.com/omacom/omarchy/blob/quattro/default/hypr/looknfeel.lua): separate motion curves and durations for windows, fades and shell layers.
- [yabai mouse support](https://github.com/asmvik/yabai/wiki/Configuration#mouse-support): center swap/stack and edge insertion drop zones.
- [yabai settings](https://github.com/asmvik/yabai/blob/master/doc/yabai.asciidoc): window animations, opacity, focus and mouse controls.
