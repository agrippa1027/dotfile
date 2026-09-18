local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")

local apple = sbar.add("item", "apple.logo", {
	position = "left",

	icon = {
		string = icons.apple,
		color = colors.cyan,
		font = { size = 18 },
	},

	label = { drawing = false },
	background = { color = colors.transparent },
	popup = { height = 32 },
})

local function close()
	apple:set({ popup = { drawing = false } })
end

-- Entries for the apple menu popup.
local entries = {
	{ "settings", icons.gear, "System Settings", "open -a 'System Settings'" },
	{ "activity", icons.cpu, "Activity Monitor", "open -a 'Activity Monitor'" },
	{
		"bluetooth",
		"",
		"Bluetooth settings",
		"open 'x-apple.systempreferences:com.apple.BluetoothSettings'",
	},
}

for _, entry in ipairs(entries) do
	local item = sbar.add("item", "apple." .. entry[1], {
		position = "popup." .. apple.name,
		icon = entry[2],
		label = entry[3],
	})
	item:subscribe("mouse.clicked", function()
		sbar.exec(entry[4])
		close()
	end)
end

-- Toggle the apple menu popup on mouse click and close on mouse exit.
apple:subscribe("mouse.clicked", function()
	apple:set({ popup = { drawing = "toggle" } })
end)
apple:subscribe({ "mouse.exited", "mouse.exited.global" }, close)

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
