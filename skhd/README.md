# Omarchy-style shortcuts for macOS

Option (⌥) controls windows and Spaces. Command (⌘) app-launch shortcuts remain
listed below. Native Command+Tab, Command+A/F/S/O/K, and Command+Delete are
available to apps. Option+Delete also keeps its native word-deletion behavior.

| Shortcut | Action |
| --- | --- |
| ⌘ Return | New Ghostty terminal |
| ⌘ ⌥ Return | Ghostty with the persistent tmux Work session |
| ⌘ ⇧ Return | Firefox |
| ⌘ ⇧ F | Finder |
| ⌘ ⇧ E | Zed |
| ⌘ ⇧ N | Neovim terminal when installed; Zed otherwise |
| ⌘ ⇧ O | Obsidian |
| ⌘ ⇧ A | ChatGPT website |
| ⌥ K | This shortcut reference |
| ⌃ ⌥ L | Lock the screen |
| ⌥ arrows | Focus a window; cross to the adjacent display at an edge |
| ⌥ ⇧ arrows | Swap tiled windows |
| ⌥ 1…9, 0, A | Focus the named Space |
| ⌥ ⇧ 1…9, 0 | Send the window to that Space and follow |
| ⌃ ⌥ ⇧ 1…9, 0 | Send the window there without following |
| ⌥ N / ⌥ P | Next / previous Space, wrapping and skipping native fullscreen |
| ⌥ Escape | Previously focused Space |
| ⌥ Tab | Next window on the current Space |
| ⌥ ⇧ Tab | Move the entire current Space to the next monitor and follow it |
| ⌃ ⌥ Tab / ⌃ ⌥ ⇧ Tab | Next / previous monitor |
| ⌥ T | Toggle floating |
| ⌥ J | Toggle tile split orientation |
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

Space `a` is available with Option+A, through SketchyBar, and desktop cycling.
Command+A stays Select All. Native Space labels use the internal prefix `ws-`
(for example, `ws-0`); shortcuts and the bar show only the final character.
Moving a Space preserves its windows as a separate desktop on the destination
monitor. When moving a display's last Space, macOS requires an empty desktop
to remain behind; the helper creates one automatically.
Swapping and split/zoom controls operate on tiled
windows; toggle a floating window back into tiling first when needed.

Opacity affects text and content as well as backgrounds. Use Ghostty's own
background opacity setting when you want transparent terminal backgrounds with
fully opaque text. Sticky windows appear on Spaces on their current display.
Disabling sticky also returns that window to tiling.

Shortcuts are adapted from the [Omarchy manual](https://learn.omacom.io/2/the-omarchy-manual/53/hotkeys).
The config is `~/.config/skhd/skhdrc`; helper actions are in `wm.sh`.
SketchyBar, tiling, and shortcuts are separate services. macOS must grant
Accessibility access to yabai and skhd; window animations also need Screen
Recording access for yabai. Secure Keyboard Entry prevents skhd from receiving keys.
