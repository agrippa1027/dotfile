local colors = require("colors")

sbar.bar({
  position = "top",
  height = 36,
  notch_display_height = 36,
  margin = 0,
  y_offset = 0,
  hidden = false,
  color = colors.bar.bg,
  border_width = 1,
  border_color = colors.bg2,
  corner_radius = 0,
  padding_left = 12,
  padding_right = 12,
  blur_radius = 0,
  shadow = false,
  topmost = true,
  display = "all",
  font_smoothing = true,
})
