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
	color = colors.bar.glass,
	border_width = 1,
	border_color = colors.bar.glass_border,
	corner_radius = settings.corner_radius,
	blur_radius = 50,
	shadow = false,

	-- Content spacing
	padding_left = settings.bar.padding_left,
	padding_right = settings.bar.padding_right,

	-- Visibility and placement
	hidden = false,
	display = "all",
	-- Keep SketchyBar above the auto-hidden native macOS menu bar.
	topmost = true,

	-- Text rendering
	font_smoothing = true,
})
