# Omarchy-style shortcuts for macOS

Option (⌥) controls windows and Spaces. Command (⌘) app-launch shortcuts remain
listed below. Native Command+Tab, Command+A/F/S/O/K, and Command+Delete are
available to apps. Option+Delete also keeps its native word-deletion behavior.

| Shortcut | Action |
| --- | --- |
| ⌘ Return | New tiled Ghostty terminal on Space 9; follow it |
| ⌘ ⌥ Return | Ghostty with the persistent tmux Work session |
| ⌘ ⇧ Return | Firefox |
| ⌘ ⇧ F | Finder |
| ⌘ ⇧ E | Zed |
| ⌘ ⇧ L | Append a timestamp to today's log and open it in a floating Zed window |
| ⌘ ⇧ N | Neovim terminal when installed; Zed otherwise |
| ⌘ ⇧ A | ChatGPT website |
| ⌃ ⌥ L | Lock the screen |
| ⌘ ⌃ A / N / B / P | Toggle audio / network / Bluetooth / power panel |
| ⌘ ⌃ ⌥ D | Toggle calendar panel |
| ⌘ ⌃ Escape | Close the active panel |
| ⌥ H / J / K / L | Focus west / south / north / east; cross to the adjacent display at an edge |
| ⌥ ⇧ H / J / K / L | Swap tiled windows west / south / north / east |
| ⌥ 1…9, 0, A | Focus the named Space |
| ⌥ ⇧ 1…9, 0 | Send the window to that Space and follow |
| ⌃ ⌥ ⇧ 1…9, 0 | Send the window there without following |
| ⌥ N / ⌥ P | Next / previous managed Space in `1–9, 0, a` order, wrapping across monitors |
| ⌥ Escape | Previously focused Space |
| ⌥ Tab | Previously focused Space |
| ⌥ ⇧ Tab | Move the entire current Space to the next monitor and follow it |
| ⌃ ⌥ Tab / ⌃ ⌥ ⇧ Tab | Next / previous monitor |
| ⌥ T | Toggle floating |
| ⌥ F | Fill the current Space; toggle again to restore |
| ⌃ ⌥ F | Native macOS fullscreen |
| ⌥ O | Toggle sticky and floating together |
| ⌥ S | Show/hide the scratchpad |
| ⌃ ⌥ S | Assign the focused window as the scratchpad |
| ⌃ ⌥ Backspace | Toggle whole-window opacity between 100% and 90% |
| ⌃ ⌥ ⇧ Backspace | Toggle the current Space’s inner gaps |
| ⌥ = / ⌥ − | Grow / shrink window width |
| ⌥ ⇧ = / ⌥ ⇧ − | Grow / shrink window height |
| ⌥ ⇧ Space | Show/hide SketchyBar |
| ⌃ ⌥ ⇧ R | Reload yabai configuration and shortcuts |
| ⌥ drag / ⌥ right-drag | Move / resize windows |

To rearrange tiles, hold Option before left-clicking and dragging a window.
Drop in another tile's center to swap, or near an edge to insert on that side.
Release the mouse before Option. Dragging from the window body also works;
there must be another tiled window on the desktop to swap with.

Space `a` is available with Option+A, through SketchyBar, and desktop cycling.
Command+A stays Select All. Native Space labels use the internal prefix `ws-`
(for example, `ws-0`); shortcuts and the bar show only the final character.
Option+N/P follows that label order rather than macOS's display-grouped native
indices. It skips native fullscreen and unmanaged desktops. Native ordering is
also kept strict within each monitor without changing monitor assignments;
unnamed desktops are retained after the managed Spaces. See the
[ordering checks and repair commands](../yabai/README.md#strict-space-ordering).
Moving a Space preserves its windows as a separate desktop on the destination
monitor. When moving a display's last Space, macOS requires an empty desktop
to remain behind; the helper creates one automatically. The destination's
workspace order is repaired after the move.
Swapping and split/zoom controls operate on tiled
windows; toggle a floating window back into tiling first when needed.

Opacity affects text and content as well as backgrounds. Use Ghostty's own
background opacity setting when you want transparent terminal backgrounds with
fully opaque text. Sticky windows appear on Spaces on their current display.
Disabling sticky also returns that window to tiling.

Shortcuts are adapted from the [Omarchy manual](https://learn.omacom.io/2/the-omarchy-manual/53/hotkeys).
The config is `~/.config/skhd/skhdrc`; helper actions are in `wm.sh`.
The daily log launcher is `log.sh`. It creates `~/Log/YYYY-MM-DD.md` when
needed, uses the existing date-heading style, and appends `## HH:MM` in local
time on each press. It reuses the Zed Log workspace, brings it to the current
desktop, and places the cursor below the timestamp. The Log folder remains
the project root for browsing other entries. Save edits before pressing the
shortcut again so Zed can reload the appended timestamp from disk.
Panel shortcuts use Command as Omarchy's Super key and share the same popup
lifecycle as clicking the bar. Repeating a shortcut closes its panel; opening
another closes the previous one and stops its telemetry. Plain Escape, Tab,
and arrow keys remain available to applications; in-panel keyboard navigation
is not implemented yet.

SketchyBar, tiling, and shortcuts are separate services. macOS must grant
Accessibility access to yabai and skhd; window animations also need Screen
Recording access for yabai. Secure Keyboard Entry prevents skhd from receiving keys.
