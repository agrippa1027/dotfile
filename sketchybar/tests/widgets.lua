local root = arg[1] or "sketchybar"
package.path = root .. "/?.lua;" .. package.path

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local items, commands, pending, timers = {}, {}, {}, {}
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
local pointer = { x = 1000, y = 1000 }
local held_pointer
local hold_pointer = false
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
		local position = self.properties.position or "right"
		local origin, children = { 10, 5 }, {}
		if position:match("^popup%.") then
			origin = { 5, 45 }
		end
		for _, child in ipairs(items) do
			if items[child.name] == child and child.properties.position == "popup." .. self.name then
				children[#children + 1] = child.name
			end
		end
		return {
			popup = {
				drawing = self.properties.popup.drawing and "on" or "off",
				items = children,
				background = { border_width = 1 },
			},
			geometry = { background = { padding_left = 5, padding_right = 5 } },
			bounding_rects = { ["display-1"] = { origin = origin, size = { 100, 30 } } },
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
	if command:find("CGEventGetLocation", 1, true) then
		if hold_pointer then
			held_pointer = callback
		else
			callback(tostring(pointer.x) .. " " .. tostring(pointer.y))
		end
		return
	end
	commands[#commands + 1] = command
	if callback then
		pending[#pending + 1] = { command = command, callback = callback }
	end
end
function api.remove(pattern)
	for name in pairs(items) do
		if type(name) == "string" and name:match("^volume%.device%.") then
			items[name] = nil
		end
	end
end
function api.delay(_, callback)
	timers[#timers + 1] = callback
end
local function flush()
	local current = timers
	timers = {}
	for _, callback in ipairs(current) do
		callback()
	end
end
local function reply(command, value)
	for i, request in ipairs(pending) do
		if request.command == command then
			table.remove(pending, i)
			request.callback(value, 0)
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
local function exit(name)
	-- Model item exits independently of native popup-frame global exits.
	if items[name].handlers["mouse.exited"] then
		emit(name, "mouse.exited")
	end
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
equal(items["widgets.volume2"].properties.label.font.family, require("settings").font.icon, "Volume glyph font")

-- Lock action commands and widget data before consolidating popup behavior.
emit("apple.bluetooth", "mouse.clicked")
equal(commands[#commands], "open 'x-apple.systempreferences:com.apple.BluetoothSettings'", "Bluetooth action")
emit("apple.logo", "mouse.clicked")
equal(items["apple.logo"].properties.popup.drawing, true, "Apple click opens")
emit("popup.events", "mouse.exited.global")
flush()
equal(items["apple.logo"].properties.popup.drawing, false, "Apple global exit closes")

emit("widgets.battery", "routine")
reply("pmset -g batt", "Now drawing from 'Battery Power'\n -InternalBattery-0 9%; discharging; 1:25 remaining")
equal(items["widgets.battery"].properties.label.string, "09%", "Battery percentage")
equal(items["widgets.battery"].properties.icon.color, require("colors").red, "Low battery color")
emit("widgets.battery", "mouse.clicked")
reply("pmset -g batt", " 9%; discharging; 1:25 remaining")
equal(items[child("widgets.battery")].properties.label, "1:25h", "Battery estimate")
emit("popup.events", "mouse.exited.global")
flush()
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

emit("widgets.volume1", "volume_change", { INFO = "9" })
equal(items["widgets.volume1"].properties.label, "09%", "Volume percentage")
emit("widgets.volume2", "mouse.clicked")
reply("SwitchAudioSource -t output -c", "Built-in")
reply("SwitchAudioSource -a -t output", "Built-in\nHeadphones\n")
equal(items["volume.device.0"].properties.label.string, "Built-in", "Output device row")
equal(items["volume.device.1"].properties.label.string, "Headphones", "Second output row")
emit("popup.events", "mouse.exited.global")
flush()
equal(items["widgets.volume.bracket"].properties.popup.drawing, false, "Volume global exit closes")
equal(items["volume.device.0"], nil, "Closing volume removes output rows")
emit("widgets.volume2", "mouse.clicked", { BUTTON = "right" })
equal(
	commands[#commands],
	"open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'",
	"Sound settings action"
)

if arg[2] == "--popup-regressions" then
	equal(items["popup.events"].properties.updates, true, "Global exit receiver always updates")
	equal(
		items["widgets.battery"].handlers["mouse.exited.global"],
		nil,
		"Owner global subscription cannot suppress re-entry"
	)
	for _, owner in ipairs({ "apple.logo", "widgets.battery", "widgets.wifi" }) do
		emit(owner, "mouse.clicked")
		local row = child(owner)
		emit(row, "mouse.entered")
		exit(row)
		flush()
		equal(items[owner].properties.popup.drawing, false, owner .. " closes after leaving its popup row")
	end

	emit("apple.logo", "mouse.clicked")
	emit("apple.logo", "mouse.entered")
	emit("apple.logo", "mouse.exited")
	emit("apple.settings", "mouse.entered")
	flush()
	equal(items["apple.logo"].properties.popup.drawing, true, "Owner to popup remains open")
	pointer = { x = 2, y = 60 }
	exit("apple.settings")
	flush()
	equal(items["apple.logo"].properties.popup.drawing, true, "Hovering popup padding stays open")
	pointer = { x = 1000, y = 1000 }
	emit("apple.settings", "mouse.entered")
	exit("apple.settings")
	emit("apple.activity", "mouse.entered")
	flush()
	equal(items["apple.logo"].properties.popup.drawing, true, "Crossing popup rows remains open")
	exit("apple.activity")
	emit("apple.logo", "mouse.entered")
	flush()
	equal(items["apple.logo"].properties.popup.drawing, true, "Popup to owner remains open")
	emit("apple.logo", "mouse.exited")
	flush()
	equal(items["apple.logo"].properties.popup.drawing, false, "Owner to another bar item closes")

	emit("apple.logo", "mouse.clicked")
	emit("widgets.battery", "mouse.clicked")
	equal(items["apple.logo"].properties.popup.drawing, false, "Opening another popup closes the previous one")
	emit("popup.events", "mouse.exited.global")

	-- A bracket owns volume, and its slider/output rows share the lifecycle.
	emit("widgets.volume2", "mouse.clicked")
	emit("widgets.volume2", "mouse.entered")
	emit("widgets.volume2", "mouse.exited")
	emit("widgets.volume1", "mouse.entered")
	flush()
	equal(items["widgets.volume.bracket"].properties.popup.drawing, true, "Moving between volume triggers stays open")
	reply("SwitchAudioSource -t output -c", "Built-in")
	reply("SwitchAudioSource -a -t output", "Built-in\nHeadphones\n")
	emit("widgets.volume1", "mouse.exited")
	emit(child("widgets.volume.bracket"), "mouse.entered")
	flush()
	equal(items["widgets.volume.bracket"].properties.popup.drawing, true, "Volume slider stays usable")
	exit(child("widgets.volume.bracket"))
	emit("volume.device.0", "mouse.entered")
	flush()
	equal(items["widgets.volume.bracket"].properties.popup.drawing, true, "Slider to output row stays open")
	exit("volume.device.0")
	flush()
	equal(items["widgets.volume.bracket"].properties.popup.drawing, false, "Leaving output row closes volume popup")
	equal(items["volume.device.0"], nil, "Row exit removes output rows")

	-- Reopening must install handlers on recreated dynamic output rows.
	emit("widgets.volume2", "mouse.clicked")
	reply("SwitchAudioSource -t output -c", "Built-in")
	reply("SwitchAudioSource -a -t output", "Built-in\n")
	emit("volume.device.0", "mouse.entered")
	exit("volume.device.0")
	flush()
	equal(
		items["widgets.volume.bracket"].properties.popup.drawing,
		false,
		"Recreated output row still closes popup at host boundary"
	)

	-- Slow shell results from a closed or replaced popup cannot recreate rows.
	emit("widgets.volume2", "mouse.clicked")
	reply("SwitchAudioSource -t output -c", "Built-in")
	emit("popup.events", "mouse.exited.global")
	emit("widgets.volume2", "mouse.clicked")
	reply("SwitchAudioSource -a -t output", "Stale output\n")
	equal(items["volume.device.0"], nil, "Old session result cannot populate reopened popup")
	reply("SwitchAudioSource -t output -c", "Built-in")
	emit("popup.events", "mouse.exited.global")
	reply("SwitchAudioSource -a -t output", "Built-in\n")
	equal(items["volume.device.0"], nil, "Closed popup ignores delayed output results")

	emit("apple.logo", "mouse.clicked")
	hold_pointer = true
	emit("apple.settings", "mouse.entered")
	exit("apple.settings")
	flush()
	emit("apple.logo", "mouse.entered")
	held_pointer("1000 1000")
	equal(items["apple.logo"].properties.popup.drawing, true, "Async pointer result cannot close after re-entry")
	exit("apple.logo")
	flush()
	emit("popup.events", "mouse.exited.global")
	emit("apple.logo", "mouse.clicked")
	held_pointer("1000 1000")
	equal(items["apple.logo"].properties.popup.drawing, true, "Async pointer result cannot close reopened popup")
	exit("apple.logo")
	flush()
	held_pointer(". -.")
	equal(items["apple.logo"].properties.popup.drawing, true, "Malformed pointer result is ignored")
	hold_pointer = false
	pointer = { x = 2, y = 60 }
	exit("apple.logo")
	flush()
	equal(items["apple.logo"].properties.popup.drawing, true, "Direct owner to popup padding stays open")
	emit("popup.events", "mouse.exited.global")
end
print("Widget behavior: " .. checks .. " assertions passed")
