local root = assert(os.getenv("CONFIG_DIR"), "SketchyBar CONFIG_DIR is missing")
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
package.cpath = root .. "/runtime/?.so;" .. package.cpath
local sbar = require("sketchybar")

sbar.begin_config()
require("bar")
require("default")
require("items.apple")
require("items.workspaces")
require("items.raycast_menu")
require("items.calendar")
require("items.widgets.battery")
require("items.widgets.volume")
require("items.widgets.wifi")
sbar.end_config()
sbar.exec("/opt/homebrew/bin/sketchybar --update")
sbar.event_loop()
