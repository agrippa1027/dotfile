# SketchyBar

Lua configuration using the official SbarLua API. Hubbamax colours and Comic Code labels, with compact coloured sections and Raycast integration for application menus. Community icons and current FelixKratz volume/battery/calendar modules are reused; pinned sources and adaptations are documented in [vendor/README.md](vendor/README.md).

Controls:

- Workspace numbers/app glyphs switch AeroSpace workspaces. Workspaces 1–3 remain available; other empty workspaces are hidden.
- Apple icon opens the settings popup, including Bluetooth settings.
- Wi-Fi opens connection, network name, IP, router, and interface details plus Wi-Fi settings.
- Speaker or volume percentage opens the volume slider and audio-output picker. Scroll adjusts volume; right-click opens Sound settings.
- Battery opens its remaining-time estimate. Right-click opens Battery settings.
- Date/time opens Calendar.
- Left-click `Menu` to open Raycast's searchable menu commands for the focused application. Raycast can omit some commands; right-click `Menu` or press **Alt-M** to reveal the complete native menu bar. In Zed, **Cmd-Shift-X** opens Extensions directly.

Wi-Fi refreshes every 30 seconds and on wake/click. Current macOS no longer provides reliable `wifi_change` events and redacts SSID without Location authorization. A redacted name is shown as “Hidden by macOS”; it does not falsely imply disconnection. “Connected” describes Wi-Fi link/address status, not a test of Internet reachability.

Install SbarLua after installing SketchyBar and Homebrew Lua 5.5:

```sh
~/.config/scripts/install-sketchybar-lua.sh
brew services start sketchybar
```

The compiled runtime is ignored by Git and rebuilt locally from a pinned upstream revision. When Lua's minor ABI changes, update the pin to a compatible upstream revision and rebuild. A tiny shell launcher loads the bundled app font and replaces the prior Lua event loop on reload; all widget logic and callbacks are Lua.

```sh
sketchybar --reload
aerospace reload-config
~/.config/scripts/check-configs.sh
```

The floating opaque bar has rounded corners and 8-point horizontal margins. It uses `topmost=on` to cover the auto-hidden native menu bar during normal use. AeroSpace reserves a 48-point top gap. To disable SketchyBar, stop its Homebrew service, restore `outer.top = 8` in AeroSpace, and re-enable the native menu bar.
