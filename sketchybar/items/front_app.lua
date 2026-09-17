local colors = require("colors")
local utils = require("lib.utils")
local app_icons = require("vendor.app-font.icon_map")

local app_icon = sbar.add("item", "front_app.icon", {
  position = "left",
  icon = { string = ":default:", color = colors.black, font = { family = "sketchybar-app-font", style = "Regular", size = 17 } },
  label = { drawing = false },
  background = { color = colors.green, corner_radius = 5 },
  padding_left = 7,
  padding_right = 0,
})
sbar.add("item", "front_app.separator", {
  position = "left",
  icon = { string = "", color = colors.green, font = { family = "Hack Nerd Font", size = 20 }, padding_left = 0, padding_right = 0 },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = -3,
  padding_right = 1,
})
local app_name = sbar.add("item", "front_app", {
  position = "left",
  icon = { drawing = false },
  label = { string = "Desktop", max_chars = 18, color = colors.white, font = { style = "Bold" } },
  background = { drawing = false },
})

local function update(app)
  app = utils.trim(app)
  if app == "" then app = "Desktop" end
  app_icon:set({ icon = app_icons[app] or ":default:" })
  app_name:set({ label = app })
end
app_name:subscribe("front_app_switched", function(env) update(env.INFO) end)
app_name:subscribe({ "forced", "system_woke" }, function()
  sbar.exec("/opt/homebrew/bin/aerospace list-windows --focused --format '%{app-name}'", update)
end)
local function popup()
  sbar.set("apple.logo", { popup = { drawing = "toggle" } })
end
app_name:subscribe("mouse.clicked", popup)
app_icon:subscribe("mouse.clicked", popup)
