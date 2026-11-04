local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")

sbar.bar({
	-- Geometry
	position = "top",
	height = settings.bar.height,
	margin = settings.bar.margin,
	y_offset = settings.bar.y_offset,

	-- Appearance
	color = colors.bar.bg,
	corner_radius = 0,
	border_width = 0,
	blur_radius = settings.bar.blur_radius,
	shadow = false,

	-- Content spacing
	padding_left = settings.bar.padding_left,
	padding_right = settings.bar.padding_right,

	-- Visibility and placement
	hidden = false,
	display = "all",
	topmost = false,

	-- Text rendering
	font_smoothing = true,
})
