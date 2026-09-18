local colors = require("colors")

sbar.bar({
  position = "top",
  height = 36,
  notch_display_height = 36,
  margin = 8,
  y_offset = 0,
  hidden = false,
  color = colors.bar.bg,
  border_width = 1,
  border_color = colors.bg2,
  corner_radius = 9,
  padding_left = 12,
  padding_right = 12,
  blur_radius = 0,
  shadow = true,
  topmost = true,
  display = "all",
  font_smoothing = true,
})
