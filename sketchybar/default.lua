local sbar = require("sketchybar")
local settings = require("settings")
local colors = require("colors")
-- Adapted from FelixKratz/dotfiles; see vendor/README.md (GPL-3.0).

-- Equivalent to the --default domain
sbar.default({
  updates = "when_shown",

  icon = {
    font = {
      family = settings.font.icon,
      style = settings.font.style_map["Bold"],
      size = 14.0
    },
    color = colors.white,
    padding_left = settings.paddings,
    padding_right = settings.paddings,
    background = { image = { corner_radius = 9 } },
  },

  label = {
    font = {
      family = settings.font.text,
      style = settings.font.style_map["Semibold"],
      size = 13.0
    },
    color = colors.white,
    padding_left = settings.paddings,
    padding_right = settings.paddings,
  },

  background = {
    drawing = true,
    height = 26,
    corner_radius = 5,
    color = colors.transparent,
    border_width = 0,
    border_color = colors.bg2,
    image = {
      corner_radius = 9,
      border_color = colors.grey,
      border_width = 1
    }
  },
  popup = {
    background = {
      border_width = 1,
      corner_radius = 7,
      border_color = colors.popup.border,
      color = colors.popup.bg,
      shadow = { drawing = false },
    },
    blur_radius = 0,
  },
  padding_left = 5,
  padding_right = 5,
  scroll_texts = false,
})
