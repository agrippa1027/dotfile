local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("lib.popup")

local apple = sbar.add("item", "apple.logo", {
	position = "left",

	icon = {
		string = icons.apple,
		color = colors.cyan,
		font = { size = 18 },
	},

	label = { drawing = false },
	background = { color = colors.transparent },
	popup = { height = settings.popup.apple_height },
})

local menu = popup.bind(apple)

-- Entries for the apple menu popup.
local entries = {
	{ "settings", icons.gear, "System Settings", settings.commands.settings },
	{ "activity", icons.cpu, "Activity Monitor", settings.commands.activity },
	{
		"bluetooth",
		icons.bluetooth,
		"Bluetooth settings",
		settings.commands.bluetooth,
	},
}

for _, entry in ipairs(entries) do
	local item = sbar.add("item", "apple." .. entry[1], {
		position = "popup." .. apple.name,
		icon = entry[2],
		label = entry[3],
	})
	menu:watch(item)
	item:subscribe("mouse.clicked", function()
		sbar.exec(entry[4])
		menu:close()
	end)
end

-- Hidden event receiver keeps Alt-M usable while native menus are showing.
sbar.add("event", "native_menus_toggle")
local menu_state = sbar.add("item", "menu_state", {
	drawing = false,
	updates = true,
})

menu_state:subscribe("native_menus_toggle", function()
	local native_visible = sbar.query("bar").hidden == "on"
	local autohide = native_visible and "true" or "false"
	sbar.exec(
		'osascript -e \'tell application "System Events" to set autohide menu bar of dock preferences to '
			.. autohide
			.. "'",
		function(_, status)
			if status == 0 then
				sbar.bar({ hidden = not native_visible, topmost = true })
			end
		end
	)
end)
