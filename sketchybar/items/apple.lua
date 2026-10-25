local sbar = require("sketchybar")

-- Hidden event receiver keeps Alt-M usable while native menus are showing.
sbar.add("event", "native_menus_toggle")
local menu_state = sbar.add("item", "menu_state", {
	drawing = false,
	updates = true,
})

menu_state:subscribe("native_menus_toggle", function()
	local native_visible = sbar.query("bar").hidden == "on"
	local autohide = native_visible and "true" or "false"
	sbar.exec(
		'osascript -e \'tell application "System Events" to set autohide menu bar of dock preferences to '
			.. autohide
			.. "'",
		function(_, status)
			if status == 0 then
				sbar.bar({ hidden = not native_visible })
			end
		end
	)
end)
