local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("lib.popup")
local panel = require("lib.panel")

local width = settings.popup.width
local bluetooth = sbar.add("item", "widgets.bluetooth", {
	position = "right",
	update_freq = 60,
	icon = { string = icons.bluetooth, color = colors.grey },
	label = { drawing = false },
	background = { color = colors.transparent },
	popup = {
		align = "right",
		height = settings.popup.height,
		blur_radius = 0,
		background = {
			color = colors.popup.bg,
			border_color = colors.accent,
			border_width = settings.popup.border_width,
			corner_radius = settings.popup.corner_radius,
		},
	},
})

local heading = sbar.add("item", "widgets.bluetooth.heading", {
	position = "popup." .. bluetooth.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	align = "center",
	icon = { string = icons.bluetooth, color = colors.accent },
	label = { string = "Bluetooth", color = colors.white },
})

panel.heading(heading)

local status_item = sbar.add("item", "widgets.bluetooth.status", {
	position = "popup." .. bluetooth.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = {
		string = "STATUS",
		color = colors.grey,
		width = 82,
		align = "left",
		font = { family = settings.font.text, size = 10 },
	},
	label = {
		string = "Checking…",
		color = colors.grey,
		width = width - 102,
		align = "right",
		font = { family = settings.font.text, size = 12 },
	},
})

local devices_heading = sbar.add("item", "widgets.bluetooth.devices", {
	position = "popup." .. bluetooth.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = { drawing = false },
	label = { string = "CONNECTED DEVICES" },
})
panel.section(devices_heading)

local device_items = {}
for index = 1, 4 do
	device_items[index] = sbar.add("item", "widgets.bluetooth.device." .. index, {
		position = "popup." .. bluetooth.name,
		width = width,
		background = { padding_left = 0, padding_right = 0 },
		drawing = false,
		icon = { string = "•", color = colors.accent, width = 24, align = "center" },
		label = {
			color = colors.white,
			width = width - 44,
			align = "left",
			max_chars = 30,
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 12 },
		},
	})
end

local empty_state = sbar.add("item", "widgets.bluetooth.empty", {
	position = "popup." .. bluetooth.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = { drawing = false },
	label = {
		string = "Checking connected devices…",
		color = colors.grey,
		font = { family = settings.font.text, size = 12 },
	},
})

local open_settings = sbar.add("item", "widgets.bluetooth.settings", {
	position = "popup." .. bluetooth.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	align = "center",
	icon = { drawing = false },
	label = { string = "Manage devices  →", color = colors.blue, font = { family = settings.font.text, size = 12 } },
})

local settings_action = panel.action(open_settings)

local power_command = "/usr/bin/defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null"
local inventory_command = "/usr/sbin/system_profiler SPBluetoothDataType -json -detailLevel mini 2>/dev/null"

local function render(powered, names)
	if powered ~= nil then
		bluetooth:set({ icon = { color = powered and colors.white or colors.grey } })
	end
	-- A power-only check cannot replace the last device inventory.
	if powered and not names then
		return
	end
	names = names or {}
	status_item:set({
		label = {
			string = powered == nil and "Unavailable"
				or (not powered and "Radio off")
				or (#names == 0 and "No devices connected" or string.format("%d connected", #names)),
			color = powered and #names > 0 and colors.accent or colors.grey,
		},
	})
	devices_heading:set({
		label = #names > #device_items and "CONNECTED DEVICES · MORE IN SETTINGS" or "CONNECTED DEVICES",
	})
	empty_state:set({
		drawing = #names == 0,
		label = powered == nil and "Device status unavailable"
			or (not powered and "Bluetooth is turned off")
			or "Connect a device in settings",
	})

	for index, item in ipairs(device_items) do
		local name = names[index]
		item:set({ drawing = name ~= nil, label = name or "" })
	end
end

local function render_report(report, status)
	local entries = type(report) == "table" and report.SPBluetoothDataType
	local data = type(entries) == "table" and entries[1]
	local controller = type(data) == "table" and data.controller_properties
	local powered
	if status == 0 and type(controller) == "table" then
		if controller.controller_state == "attrib_on" then
			powered = true
		elseif controller.controller_state == "attrib_off" then
			powered = false
		end
	end
	local names = {}
	local connected = type(data) == "table" and data.device_connected
	if powered and type(connected) == "table" then
		for _, device in ipairs(connected) do
			if type(device) == "table" then
				for name in pairs(device) do
					if type(name) == "string" then
						names[#names + 1] = name
						break
					end
				end
			end
		end
		table.sort(names)
	end
	render(powered, names)
end

local started_at
local generation = 0
local pending = false
local function refresh()
	local now = os.time()
	-- Native exec workers have a 60s alarm; recover on the next event after that.
	if started_at and now - started_at < 65 then
		pending = true
		return
	end
	generation = generation + 1
	local request = generation
	pending = false

	local function finish()
		started_at = nil
		if pending then
			refresh()
		end
	end

	local function inventory()
		started_at = os.time()
		sbar.exec(inventory_command, function(report, status)
			if request ~= generation then
				return
			end
			render_report(report, status)
			finish()
		end)
	end

	if popup.is_open(bluetooth) then
		inventory()
	else
		started_at = os.time()
		sbar.exec(power_command, function(result, status)
			if request ~= generation then
				return
			end
			local value = type(result) == "string" and result:match("^%s*([01])%s*$")
			if status ~= 0 or not value then
				inventory()
				return
			end
			render(value == "1")
			finish()
		end)
	end
end

bluetooth:subscribe({ "routine", "forced", "system_woke" }, refresh)
local details = popup.bind(bluetooth, {
	settings_command = settings.commands.bluetooth,
	on_open = function()
		settings_action:reset()
		refresh()
	end,
	on_close = function()
		settings_action:reset()
	end,
})
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.bluetooth)
end)

refresh()
return bluetooth
