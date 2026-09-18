local colors = require("colors")

sbar.bar({
  -- Geometry
  position = "top",
  height = 36,
  margin = 8,
  y_offset = 5,

  -- Appearance
  color = colors.bar.glass,
  border_width = 1,
  border_color = colors.bar.glass_border,
  corner_radius = 9,
  blur_radius = 45,
  shadow = false,

  -- Content spacing
  padding_left = 12,
  padding_right = 12,

  -- Visibility and placement
  hidden = false,
  display = "all",
  -- Keep SketchyBar above the auto-hidden native macOS menu bar.
  topmost = true,

  -- Text rendering
  font_smoothing = true,
})
