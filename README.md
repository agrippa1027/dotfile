# Active macOS configuration

The desktop uses yabai, skhd and the personal SketchyBar fork. Ghostty, tmux,
Zed, Firefox, Zsh/Starship, Git/GitHub settings, fonts and wallpapers remain.
Existing desktop appearance, workspace monitor assignments and editor settings
are preserved. See the [shortcut reference](skhd/README.md),
[workspace setup](yabai/README.md) and [bar controls](sketchybar/README.md).

## Cleanup on 2026-11-05

Removed the confirmed unused configurations for AeroSpace, JankyBorders, nnn,
gitui, btop, OpenCode, Yazi, Neofetch, Wireshark and ytmdl. Zed's nnn task,
launcher and two key bindings were removed with the retired shell/bootstrap,
backup and verification references. Applications and external credential stores
were not uninstalled or erased.

Removed unused tmux themes and its theme wrapper, the unloaded SketchyBar menu
backup/receiver, and the unused app-icon font/map and startup load. Active
Hubbamax, Comic Code and Hack/Maple fonts remain. The duplicate Alt-J split
binding was removed in favor of directional focus; bar/window reservation now
matches the chosen 30px height.

The display panel keeps the picker, brightness slider/presets, mode information
and Refresh/BetterDisplay footer. Repeated labels and persistent success rows
were removed. Periodic updates read only identity and brightness: three CLI
queries for two displays, versus eight for a full inventory. Opening/refreshing
still reads mode details. Verified changes do not trigger another full read.
No CPU or battery benchmark is implied by these command counts.

The managed Zsh config preserves the current shell aliases, removes OpenCode's
PATH entry and duplicate pnpm initialization, and keeps NVM lazy loading and
cached completion. `~/.zshrc` now links to this managed config. Its previous
separate copy is preserved at
`~/.config-backups/config-cleanup-20261105-020747/zshrc`.
Shell secrets remain outside Git.

## Verification

```sh
scripts/check-configs.sh
scripts/backup-dotfiles.sh --dry-run
```

The checker validates the remaining tool configs and shortcuts and loads tmux
in an isolated server. [SketchyBar tests](sketchybar/tests/README.md) and
[workspace tests](yabai/README.md#strict-space-ordering) cover runtime behavior.
Bootstrap installs only the remaining core stack; it does not restore retired
applications. Git history retains the removed tracked configs.

Verification passed: the complete config checker, backup dry-run, all 208 Lua
and 37 Python checks, shell/Python lint and formatting. A read-only live display
panel check confirmed selection, mode data and stopped polling on close.
Lua diagnostics retain one pre-existing warning in the Wi-Fi test's `os.time`
mock/restore; the removed unused font map accounted for four other warnings.
