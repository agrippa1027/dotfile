local root = arg[1] or "sketchybar"
package.path = root .. "/?.lua;" .. package.path

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local items, commands, pending = {}, {}, {}
local function merge(target, source)
	for key, value in pairs(source) do
		if type(value) == "table" then
			if type(target[key]) ~= "table" then
				target[key] = {}
			end
			merge(target[key], value)
		else
			target[key] = value
		end
	end
end
local api = {}
function api.add(kind, name, members, properties)
	if type(name) ~= "string" then
		properties = type(members) == "table" and members or name
		name = "anonymous." .. tostring(#items + 1)
	elseif kind ~= "bracket" then
		properties = members
	end
	local item = { name = name, kind = kind, handlers = {}, properties = { popup = { drawing = false } } }
	merge(item.properties, properties or {})
	function item:set(values)
		if values.popup and values.popup.drawing == "toggle" then
			values = { popup = { drawing = not self.properties.popup.drawing } }
		end
		merge(self.properties, values)
	end
	function item:query()
		local children = {}
		for _, child in ipairs(items) do
			if items[child.name] == child and child.properties.position == "popup." .. self.name then
				children[#children + 1] = child.name
			end
		end
		return {
			popup = {
				drawing = self.properties.popup.drawing and "on" or "off",
				items = children,
			},
		}
	end
	function item:subscribe(events, callback)
		if type(events) == "string" then
			events = { events }
		end
		for _, event in ipairs(events) do
			self.handlers[event] = callback
		end
	end
	items[#items + 1] = item
	items[name] = item
	return item
end
function api.query(name)
	return items[name]:query()
end
function api.exec(command, callback)
	commands[#commands + 1] = command
	if callback then
		pending[#pending + 1] = { command = command, callback = callback }
	end
end
local function reply(command, value, exit_code)
	for i, request in ipairs(pending) do
		if request.command == command then
			table.remove(pending, i)
			request.callback(value, exit_code or 0)
			return
		end
	end
	error("No pending command: " .. command)
end
local function emit(name, event, env)
	local item = assert(items[name], "Missing item " .. name)
	local callback = assert(item.handlers[event], name .. " missing " .. event)
	callback(env or { BUTTON = "left" })
end
local function child(owner)
	for _, item in ipairs(items) do
		if item.properties.position == "popup." .. owner then
			return item.name
		end
	end
	error("No child for " .. owner)
end
package.preload.sketchybar = function()
	return api
end

require("items.apple")
require("items.widgets.battery")
require("items.widgets.wifi")
require("items.widgets.volume")
require("items.widgets.bluetooth")
equal(items["widgets.volume2"].properties.label.font.family, require("settings").font.icon, "Volume glyph font")

-- Lock action commands and widget data before consolidating popup behavior.
emit("apple.bluetooth", "mouse.clicked")
equal(commands[#commands], "open 'x-apple.systempreferences:com.apple.BluetoothSettings'", "Bluetooth action")
emit("apple.logo", "mouse.clicked")
equal(items["apple.logo"].properties.popup.drawing, true, "Apple click opens")
emit("apple.logo", "mouse.exited.global")
equal(items["apple.logo"].properties.popup.drawing, false, "Apple global exit closes")

emit("widgets.battery", "routine")
reply("pmset -g batt", "Now drawing from 'Battery Power'\n -InternalBattery-0 9%; discharging; 1:25 remaining")
equal(items["widgets.battery"].properties.label.string, "09%", "Battery percentage")
equal(items["widgets.battery"].properties.icon.color, require("colors").red, "Low battery color")
emit("widgets.battery", "mouse.clicked")
reply("pmset -g batt", " 9%; discharging; 1:25 remaining")
equal(items[child("widgets.battery")].properties.label, "1:25h", "Battery estimate")
emit("widgets.battery", "mouse.exited.global")
equal(items["widgets.battery"].properties.popup.drawing, false, "Battery global exit closes")
emit("widgets.battery", "mouse.clicked", { BUTTON = "right" })
equal(
	commands[#commands],
	"open 'x-apple.systempreferences:com.apple.Battery-Settings.extension'",
	"Battery settings action"
)

reply("/usr/sbin/networksetup -listallhardwareports", "Hardware Port: Wi-Fi\nDevice: en0\n")
reply("/usr/sbin/networksetup -getairportpower 'en0' 2>/dev/null", "Wi-Fi Power (en0): On")
reply("/usr/sbin/ipconfig getsummary 'en0' 2>/dev/null", "LinkStatusActive : TRUE\nRouter : 192.168.1.1")
reply("/usr/sbin/ipconfig getifaddr 'en0' 2>/dev/null", "192.168.1.2")
reply("/sbin/ifconfig 'en0' 2>/dev/null", "status: active")
equal(items["widgets.wifi.connection"].properties.label, "Connected", "Wi-Fi connected status")
equal(items["widgets.wifi.ip"].properties.label, "192.168.1.2", "Wi-Fi address")
emit("widgets.wifi.settings", "mouse.clicked")
equal(
	commands[#commands],
	"/usr/bin/open 'x-apple.systempreferences:com.apple.wifi-settings-extension'",
	"Wi-Fi settings action"
)

local bluetooth_command = "/usr/sbin/system_profiler SPBluetoothDataType -json -detailLevel mini 2>/dev/null"
reply(bluetooth_command, {
	SPBluetoothDataType = {
		{
			controller_properties = { controller_state = "attrib_on" },
			device_connected = { { Keyboard = {} }, { Mouse = {} } },
		},
	},
})
equal(items["widgets.bluetooth"].properties.icon.color, require("colors").white, "Bluetooth radio on color")
equal(items["widgets.bluetooth"].properties.label.string, "2", "Bluetooth connected-device count")
equal(items["widgets.bluetooth"].properties.label.drawing, true, "Bluetooth count is visible")
emit("widgets.bluetooth", "routine")
reply(bluetooth_command, {
	SPBluetoothDataType = { { controller_properties = { controller_state = "attrib_off" } } },
})
equal(items["widgets.bluetooth"].properties.icon.color, require("colors").grey, "Bluetooth radio off color")
equal(items["widgets.bluetooth"].properties.label.drawing, false, "Bluetooth count hides when disconnected")
emit("widgets.bluetooth", "system_woke")
reply(bluetooth_command, nil, 1)
equal(items["widgets.bluetooth"].properties.icon.color, require("colors").grey, "Unavailable Bluetooth color")
equal(items["widgets.bluetooth"].properties.label.drawing, false, "Unavailable Bluetooth hides count")
emit("widgets.bluetooth", "mouse.clicked")
equal(commands[#commands], require("settings").commands.bluetooth, "Bluetooth settings action")

emit("widgets.volume1", "volume_change", { INFO = "9" })
equal(items["widgets.volume1"].properties.label, "09%", "Volume percentage")
local volume_icons = require("icons").volume
for _, case in ipairs({
	{ 0, volume_icons._0 },
	{ 1, volume_icons._10 },
	{ 10, volume_icons._10 },
	{ 11, volume_icons._33 },
	{ 30, volume_icons._33 },
	{ 31, volume_icons._66 },
	{ 60, volume_icons._66 },
	{ 61, volume_icons._100 },
	{ 100, volume_icons._100 },
}) do
	emit("widgets.volume1", "volume_change", { INFO = tostring(case[1]) })
	equal(items["widgets.volume2"].properties.label, case[2], "Volume icon at " .. case[1])
	equal(items["widgets.volume1"].properties.label, string.format("%02d%%", case[1]), "Volume label at " .. case[1])
end
emit("widgets.volume1", "volume_change", { INFO = "invalid" })
equal(items["widgets.volume1"].properties.label, "100%", "Invalid volume leaves label unchanged")
emit("widgets.volume1", "forced")
reply("osascript -e 'output volume of (get volume settings)'", " 9\n")
equal(items["widgets.volume1"].properties.label, "09%", "Forced refresh trims volume")
for _, value in ipairs({ -1, 101, math.huge, -math.huge, 0 / 0 }) do
	emit("widgets.volume1", "volume_change", { INFO = value })
	equal(items["widgets.volume1"].properties.label, "09%", "Invalid numeric volume is ignored")
end
emit("widgets.volume1", "volume_change", { INFO = "9.5" })
equal(items["widgets.volume1"].properties.label, "10%", "Fractional volume rounds to a whole percent")
emit("widgets.volume1", "forced")
emit("widgets.volume1", "volume_change", { INFO = "42" })
reply("osascript -e 'output volume of (get volume settings)'", "9\n")
equal(items["widgets.volume1"].properties.label, "42%", "Delayed refresh cannot overwrite a volume event")
emit("widgets.volume1", "forced")
emit("widgets.volume1", "forced")
reply("osascript -e 'output volume of (get volume settings)'", "9\n")
equal(items["widgets.volume1"].properties.label, "42%", "Older refresh cannot overwrite newer refresh")
reply("osascript -e 'output volume of (get volume settings)'", "43\n")
equal(items["widgets.volume1"].properties.label, "43%", "Latest refresh updates volume")
emit("widgets.volume1", "forced")
reply("osascript -e 'output volume of (get volume settings)'", "9\n", 1)
equal(items["widgets.volume1"].properties.label, "43%", "Failed refresh leaves volume unchanged")
emit("widgets.volume1", "system_woke")
reply("osascript -e 'output volume of (get volume settings)'", "44\n")
equal(items["widgets.volume1"].properties.label, "44%", "Waking refreshes volume")
emit("widgets.volume2", "mouse.scrolled", { INFO = { delta = 1, modifier = "" } })
equal(
	commands[#commands],
	'osascript -e "set volume output volume (output volume of (get volume settings) + 10.0)"',
	"Scroll uses ten percent steps"
)
emit("widgets.volume1", "mouse.scrolled", { INFO = { delta = -1, modifier = "ctrl" } })
equal(
	commands[#commands],
	'osascript -e "set volume output volume (output volume of (get volume settings) + -1)"',
	"Control scroll uses one percent steps"
)
for _, info in ipairs({
	false,
	"invalid",
	{},
	{ delta = "invalid" },
	{ delta = "1; exit" },
	{ delta = 0 },
	{ delta = math.huge },
	{ delta = -math.huge },
	{ delta = 1e308 },
	{ delta = 0 / 0 },
}) do
	local before = #commands
	emit("widgets.volume2", "mouse.scrolled", { INFO = info })
	equal(#commands, before, "Invalid or zero scroll does not execute commands")
end
emit("widgets.volume1", "mouse.scrolled", { INFO = { delta = "-1", modifier = "ctrl" } })
equal(
	commands[#commands],
	'osascript -e "set volume output volume (output volume of (get volume settings) + -1)"',
	"Numeric scroll strings use fine steps"
)
-- Volume is a bar control without popup children or discovery commands.
equal(#items["widgets.volume.bracket"]:query().popup.items, 0, "Volume has no popup children")
for _, name in ipairs({ "widgets.volume1", "widgets.volume2" }) do
	local before = #commands
	emit(name, "mouse.clicked")
	equal(#commands, before, "Volume left click does not execute commands")
	equal(items["widgets.volume.bracket"].properties.popup.drawing, false, "Volume click does not open popup")
	emit(name, "mouse.clicked", { BUTTON = "right" })
	equal(commands[#commands], require("settings").commands.sound, "Volume right click opens Sound settings")
end

print("Widget behavior: " .. checks .. " assertions passed")
