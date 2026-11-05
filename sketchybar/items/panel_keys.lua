local sbar = require("sketchybar")
local popup = require("lib.popup")

local panels = {
	audio = "widgets.volume",
	display = "widgets.display",
	network = "widgets.wifi",
	bluetooth = "widgets.bluetooth",
	power = "widgets.battery",
	calendar = "calendar",
}

sbar.add("event", "omarchy_panel_toggle")
sbar.add("event", "omarchy_panel_close")
local receiver = sbar.add("item", "panel_keys", { drawing = false, updates = true })
receiver:subscribe("omarchy_panel_toggle", function(env)
	local name = panels[env.PANEL]
	if name then
		popup.toggle(name)
	end
end)
receiver:subscribe("omarchy_panel_close", popup.close_all)
