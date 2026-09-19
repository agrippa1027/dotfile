local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")

local function glass()
	return {
		background = {
			color = colors.bar.glass,
			border_color = colors.bar.glass_border,
			border_width = 1,
			height = 32,
			corner_radius = settings.corner_radius + 2,
			padding_left = 4,
			padding_right = 4,
		},
	}
end

sbar.add("bracket", "group.workspaces", { "apple.logo", "/workspace\\..*/", "raycast.menu" }, glass())
sbar.add("bracket", "group.calendar", { "calendar" }, glass())
sbar.add(
	"bracket",
	"group.widgets",
	{ "widgets.bluetooth", "widgets.wifi", "widgets.volume", "widgets.battery" },
	glass()
)
