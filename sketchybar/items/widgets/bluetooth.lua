local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("lib.popup")

local width = settings.popup.width
local bluetooth = sbar.add("item", "widgets.bluetooth", {
	position = "right",
	update_freq = 60,
	icon = { string = icons.bluetooth, color = colors.grey },
	label = { drawing = false },
	background = { color = colors.transparent },
	popup = { align = "center", height = settings.popup.height },
})

local heading = sbar.add("item", "widgets.bluetooth.heading", {
	position = "popup." .. bluetooth.name,
	width = width,
	align = "center",
	icon = { string = icons.bluetooth, color = colors.cyan },
	label = { string = "Bluetooth", font = { style = settings.font.style_map.Bold } },
})

local status_item = sbar.add("item", "widgets.bluetooth.status", {
	position = "popup." .. bluetooth.name,
	width = width,
	icon = { string = "Status:", width = 100, align = "left" },
	label = { string = "Checking…", width = width - 100, align = "right" },
})

local device_items = {}
for index = 1, 4 do
	device_items[index] = sbar.add("item", "widgets.bluetooth.device." .. index, {
		position = "popup." .. bluetooth.name,
		width = width,
		drawing = false,
		icon = { string = "•", color = colors.cyan, width = 24, align = "center" },
		label = { width = width - 24, align = "left", max_chars = 30 },
	})
end

local open_settings = sbar.add("item", "widgets.bluetooth.settings", {
	position = "popup." .. bluetooth.name,
	width = width,
	align = "center",
	icon = { drawing = false },
	label = { string = "Open Bluetooth Settings", color = colors.blue },
})

local command = "/usr/sbin/system_profiler SPBluetoothDataType -json -detailLevel mini 2>/dev/null"
local updating = false

local function render(report, status)
	local entries = type(report) == "table" and report.SPBluetoothDataType
	local data = type(entries) == "table" and entries[1]
	local controller = type(data) == "table" and data.controller_properties
	local powered = status == 0 and type(controller) == "table" and controller.controller_state == "attrib_on"
	local names = {}

	if powered and type(data.device_connected) == "table" then
		for _, device in ipairs(data.device_connected) do
			for name in pairs(device) do
				names[#names + 1] = name
				break
			end
		end
		table.sort(names)
	end

	bluetooth:set({ icon = { color = powered and colors.white or colors.grey } })
	status_item:set({
		label = not powered and "Radio off"
			or (#names == 0 and "No devices connected" or string.format("%d connected", #names)),
	})

	for index, item in ipairs(device_items) do
		local name = names[index]
		item:set({ drawing = name ~= nil, label = name or "" })
	end
end

local function refresh()
	if updating then
		return
	end
	updating = true
	sbar.exec(command, function(report, status)
		updating = false
		render(report, status)
	end)
end

bluetooth:subscribe({ "routine", "forced", "system_woke" }, refresh)
local details = popup.bind(bluetooth, { settings_command = settings.commands.bluetooth, on_open = refresh })
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.bluetooth)
end)

refresh()
return bluetooth
