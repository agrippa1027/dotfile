local root = assert(os.getenv("CONFIG_DIR"), "SketchyBar CONFIG_DIR is missing")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
package.cpath = root .. "/runtime/?.so;" .. package.cpath
local sbar = require("sketchybar")

sbar.begin_config()
require("bar")
require("default")
require("items.workspaces")

require("items.calendar")
require("items.widgets.battery")
require("items.widgets.volume")
require("items.widgets.display")
require("items.widgets.wifi")
require("items.widgets.bluetooth")

require("items.panel_keys")
sbar.end_config()
sbar.exec("$HOME/.local/bin/sketchybar --update")
sbar.event_loop()
