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
		label = powered == nil and "Unavailable"
			or (not powered and "Radio off")
			or (#names == 0 and "No devices connected" or string.format("%d connected", #names)),
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
	if powered and type(data.device_connected) == "table" then
		for _, device in ipairs(data.device_connected) do
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

	if bluetooth:query().popup.drawing == "on" then
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
local details = popup.bind(bluetooth, { settings_command = settings.commands.bluetooth, on_open = refresh })
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.bluetooth)
end)

refresh()
return bluetooth
