local sbar = require("sketchybar")
local colors = require("colors")

sbar.bar({
  -- Geometry
  position = "top",
  height = 38,
  margin = 4,
  y_offset = 5,

  -- Appearance
  color = colors.bar.glass,
  border_width = 1,
  border_color = colors.bar.glass_border,
  corner_radius = 9,
  blur_radius = 50,
  shadow = false,

  -- Content spacing
  padding_left = 8,
  padding_right = 8,

  -- Visibility and placement
  hidden = false,
  display = "all",
  -- Keep SketchyBar above the auto-hidden native macOS menu bar.
  topmost = true,

  -- Text rendering
  font_smoothing = true,
})
