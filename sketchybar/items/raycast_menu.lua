local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")

local menu = sbar.add("item", "raycast.menu", {
	position = "left",
	icon = { drawing = false },
	label = {
		string = "Menu",
		color = colors.white,
		font = {
			family = settings.font.text,
			style = settings.font.style_map.Bold,
			size = 13,
		},
		padding_left = 8,
		padding_right = 8,
	},
	background = {
		color = colors.transparent,
		corner_radius = 7,
	},
	padding_left = 4,
	padding_right = 4,
})

menu:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		sbar.exec("/opt/homebrew/bin/sketchybar --trigger native_menus_toggle")
		return
	end
	sbar.exec("open 'raycast://extensions/raycast/navigation/search-menu-items'")
end)
