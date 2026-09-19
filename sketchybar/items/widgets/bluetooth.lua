local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local bluetooth = sbar.add("item", "widgets.bluetooth", {
	position = "right",
	update_freq = 60,
	icon = { string = icons.bluetooth, color = colors.grey },
	label = { string = "0", drawing = false },
	background = { color = colors.transparent },
})

local command = "/usr/sbin/system_profiler SPBluetoothDataType -json -detailLevel mini 2>/dev/null"
local updating = false

local function render(report, status)
	local entries = type(report) == "table" and report.SPBluetoothDataType
	local data = type(entries) == "table" and entries[1]
	local controller = type(data) == "table" and data.controller_properties
	local powered = status == 0 and type(controller) == "table" and controller.controller_state == "attrib_on"
	local connected = powered and data.device_connected or nil
	local count = type(connected) == "table" and #connected or 0

	bluetooth:set({
		icon = { color = powered and colors.white or colors.grey },
		label = { string = tostring(count), drawing = count > 0 },
	})
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
bluetooth:subscribe("mouse.clicked", function()
	sbar.exec(settings.commands.bluetooth)
end)

refresh()

return bluetooth
