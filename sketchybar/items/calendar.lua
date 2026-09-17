local settings = require("settings")
-- Adapted from FelixKratz/dotfiles; see vendor/README.md (GPL-3.0).
local colors = require("colors")

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

local cal = sbar.add("item", "calendar", {
  icon = {
    color = colors.black,
    padding_left = 8,
    font = {
      family = settings.font.numbers,
      style = settings.font.style_map["Black"],
      size = 12.0,
    },
  },
  label = {
    color = colors.black,
    padding_right = 8,
    width = 49,
    align = "right",
    font = { family = settings.font.numbers },
  },
  position = "right",
  update_freq = 30,
  padding_left = 1,
  padding_right = 1,
  background = {
    color = colors.red,
    border_color = colors.black,
    border_width = 1
  },
  click_script = "open -a 'Calendar'"
})

-- Double border for calendar using a single item bracket
sbar.add("bracket", { cal.name }, {
  background = {
    color = colors.transparent,
    height = 26,
    border_width = 0,
  }
})

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

cal:subscribe({ "forced", "routine", "system_woke" }, function(env)
  cal:set({ icon = os.date("%a. %d %b."), label = os.date("%H:%M") })
end)
