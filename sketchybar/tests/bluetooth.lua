-- Run with: lua sketchybar/tests/bluetooth.lua (from the .config directory).
-- All commands and time are mocked; the real popup bindings are exercised.
local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
local power_command = "/usr/bin/defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null"
local inventory_command = "/usr/sbin/system_profiler SPBluetoothDataType -json -detailLevel mini 2>/dev/null"
local colors = { white = "white", grey = "grey", cyan = "cyan", blue = "blue", transparent = "transparent" }
local settings = {
	popup = { width = 280, height = 30 },
	font = { style_map = { Bold = "Bold" } },
	commands = { bluetooth = "open bluetooth-settings" },
}

local function equal(actual, expected, message)
	assert(
		actual == expected,
		(message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	)
end

local function merge(target, values)
	for key, value in pairs(values) do
		if type(value) == "table" then
			target[key] = target[key] or {}
			merge(target[key], value)
		elseif (key == "label" or key == "icon") and type(target[key]) == "table" then
			target[key].string = value
		else
			target[key] = value
		end
	end
end

local function new_widget()
	local mock = { now = 1000, items = {}, commands = {} }
	local sbar = {}
	function sbar.add(_, name, properties)
		local item = { name = name, properties = properties, subscriptions = {} }
		function item:set(values)
			merge(self.properties, values)
		end
		function item:query()
			return { popup = { drawing = self.properties.popup.drawing and "on" or "off" } }
		end
		function item:subscribe(events, callback)
			for _, event in ipairs(type(events) == "table" and events or { events }) do
				self.subscriptions[event] = callback
			end
		end
		mock.items[name] = item
		return item
	end
	function sbar.exec(command, callback)
		mock.commands[#mock.commands + 1] = { command = command, callback = callback }
	end

	local modules = { sketchybar = sbar, colors = colors, icons = { bluetooth = "BT" }, settings = settings }
	local env = setmetatable({
		os = {
			time = function()
				return mock.now
			end,
		},
		require = function(name)
			return assert(modules[name], "Unexpected require: " .. name)
		end,
	}, { __index = _G })
	modules["lib.popup"] = assert(loadfile(root .. "/lib/popup.lua", "t", env))()
	mock.widget = assert(loadfile(root .. "/items/widgets/bluetooth.lua", "t", env))()

	function mock:fire(event, values)
		assert(self.widget.subscriptions[event], "Missing event: " .. event)(values or {})
	end
	function mock:reply(index, result, status)
		local request = assert(self.commands[index], "Missing command: " .. index)
		assert(not request.replied, "Callback already delivered")
		request.replied = true
		assert(request.callback, "Missing callback")(result, status)
	end
	function mock:expect_commands(expected)
		equal(#self.commands, #expected, "command count")
		for index, command in ipairs(expected) do
			equal(self.commands[index].command, command, "command " .. index)
		end
	end
	function mock:status()
		return self.items["widgets.bluetooth.status"].properties.label.string
	end
	function mock:device(index)
		return self.items["widgets.bluetooth.device." .. index].properties
	end
	function mock:expect_empty()
		for index = 1, 4 do
			equal(self:device(index).drawing, false, "device visibility")
			equal(self:device(index).label.string, "", "device label")
		end
	end
	return mock
end

local function report(powered, names)
	local devices = {}
	for _, name in ipairs(names or {}) do
		devices[#devices + 1] = { [name] = {} }
	end
	return {
		SPBluetoothDataType = {
			{
				controller_properties = { controller_state = powered and "attrib_on" or "attrib_off" },
				device_connected = devices,
			},
		},
	}
end

local passed = 0
local function test(name, run)
	run()
	passed = passed + 1
	print("ok - " .. name)
end

test("collapsed startup, 60-second polling, forced refresh and wake use defaults", function()
	local mock = new_widget()
	equal(mock.widget.properties.update_freq, 60)
	equal(mock.widget.properties.icon.string, "BT")
	equal(mock.widget.properties.label.drawing, false)
	mock:expect_commands({ power_command })
	mock:reply(1, " \t1\n", 0)
	equal(mock.widget.properties.icon.color, colors.white)
	equal(mock:status(), "Checking…")
	for index, event in ipairs({ "routine", "forced", "system_woke" }) do
		mock:fire(event)
		equal(mock.commands[index + 1].command, power_command)
		mock:reply(index + 1, "1", 0)
	end
	mock:expect_commands({ power_command, power_command, power_command, power_command })
end)

test("a valid zero means radio off without inventory", function()
	local mock = new_widget()
	mock:reply(1, "0\n", 0)
	mock:expect_commands({ power_command })
	equal(mock.widget.properties.icon.color, colors.grey)
	equal(mock:status(), "Radio off")
	mock:expect_empty()
end)

test("visible popup inventories, sorts and caps devices, and stays synced when off", function()
	local mock = new_widget()
	mock:reply(1, "1", 0)
	mock:fire("mouse.clicked", { BUTTON = "left" })
	equal(mock.widget:query().popup.drawing, "on")
	mock:reply(2, report(true, { "Zulu", "Echo", "Bravo", "Alpha", "Delta" }), 0)
	equal(mock:status(), "5 connected")
	for index, name in ipairs({ "Alpha", "Bravo", "Delta", "Echo" }) do
		equal(mock:device(index).drawing, true)
		equal(mock:device(index).label.string, name)
	end
	mock:fire("routine")
	mock:reply(3, report(false, { "Stale device" }), 0)
	equal(mock:status(), "Radio off")
	equal(mock.widget.properties.icon.color, colors.grey)
	mock:expect_empty()
	mock:fire("system_woke")
	mock:reply(4, report(true), 0)
	equal(mock:status(), "No devices connected")
	equal(mock.widget.properties.icon.color, colors.white)
	mock:expect_empty()
	mock:fire("mouse.exited.global")
	mock:fire("forced")
	mock:reply(5, "1", 0)
	mock:expect_commands({ power_command, inventory_command, inventory_command, inventory_command, power_command })
end)

test("collapsed power checks preserve inventory on, and clear stale devices off", function()
	local mock = new_widget()
	mock:reply(1, "1", 0)
	mock:fire("mouse.clicked")
	mock:reply(2, report(true, { "Keyboard" }), 0)
	mock:fire("mouse.exited.global")
	mock:fire("routine")
	mock:reply(3, "1", 0)
	equal(mock:status(), "1 connected")
	equal(mock:device(1).label.string, "Keyboard")
	mock:fire("routine")
	mock:reply(4, "0", 0)
	equal(mock:status(), "Radio off")
	mock:expect_empty()
	mock:expect_commands({ power_command, inventory_command, power_command, power_command })
end)

for _, invalid in ipairs({
	{ name = "missing value", status = 0 },
	{ name = "empty value", value = "", status = 0 },
	{ name = "unexpected number", value = "2", status = 0 },
	{ name = "boolean text", value = "true", status = 0 },
	{ name = "multiple values", value = "1\n0", status = 0 },
	{ name = "non-string value", value = {}, status = 0 },
	{ name = "failed query with zero", value = "0", status = 1 },
	{ name = "failed query with one", value = "1", status = 1 },
	{ name = "missing exit status", value = "1" },
}) do
	test("defaults fallback: " .. invalid.name, function()
		local mock = new_widget()
		mock:reply(1, invalid.value, invalid.status)
		mock:expect_commands({ power_command, inventory_command })
		equal(mock:status(), "Checking…")
		mock:reply(2, report(true, { "Headphones" }), 0)
		equal(mock.widget.properties.icon.color, colors.white)
		equal(mock:status(), "1 connected")
		equal(mock:device(1).label.string, "Headphones")
		mock:fire("routine")
		mock:reply(3, "1", 0)
		mock:expect_commands({ power_command, inventory_command, power_command })
	end)
end

test("fallback can confirm radio off", function()
	local mock = new_widget()
	mock:reply(1, "", 1)
	mock:reply(2, report(false), 0)
	equal(mock:status(), "Radio off")
	mock:expect_empty()
end)

for _, invalid in ipairs({
	{ name = "command failure", value = report(false), status = 1 },
	{ name = "missing report", status = 0 },
	{ name = "non-JSON output", value = "invalid JSON", status = 0 },
	{ name = "missing controller", value = { SPBluetoothDataType = { {} } }, status = 0 },
	{
		name = "unknown controller state",
		value = { SPBluetoothDataType = { { controller_properties = { controller_state = "unknown" } } } },
		status = 0,
	},
}) do
	test("query failure is not radio off: " .. invalid.name, function()
		local mock = new_widget()
		mock:reply(1, "1", 0)
		mock:fire("mouse.clicked")
		mock:reply(2, report(true, { "Keyboard" }), 0)
		mock:fire("mouse.exited.global")
		mock:fire("routine")
		mock:reply(3, "", 1)
		mock:reply(4, invalid.value, invalid.status)
		equal(mock.widget.properties.icon.color, colors.white)
		equal(mock:status(), "Unavailable")
		mock:expect_empty()
		mock:fire("mouse.clicked")
		mock:reply(5, report(true), 0)
		equal(mock:status(), "No devices connected")
	end)
end

for _, power in ipairs({ "1", "0" }) do
	test("popup opening during routine power " .. power .. " queues details", function()
		local mock = new_widget()
		mock:reply(1, "1", 0)
		mock:fire("routine")
		mock:fire("mouse.clicked")
		mock:fire("system_woke")
		mock:expect_commands({ power_command, power_command })
		mock:reply(2, power, 0)
		mock:expect_commands({ power_command, power_command, inventory_command })
		if power == "0" then
			equal(mock:status(), "Radio off")
			mock:expect_empty()
		end
		mock:reply(3, report(power == "1", { "Mouse" }), 0)
		equal(mock:status(), power == "1" and "1 connected" or "Radio off")
	end)
end

test("opening and closing during startup does not force hidden inventory", function()
	local mock = new_widget()
	mock:fire("mouse.clicked")
	mock:fire("mouse.exited.global")
	mock:reply(1, "1", 0)
	mock:expect_commands({ power_command, power_command })
	mock:reply(2, "1", 0)
end)

test("reopening during inventory preserves the queued details refresh", function()
	local mock = new_widget()
	mock:reply(1, "1", 0)
	mock:fire("mouse.clicked")
	mock:fire("mouse.exited.global")
	mock:fire("mouse.clicked")
	mock:reply(2, report(true, { "Old device" }), 0)
	mock:expect_commands({ power_command, inventory_command, inventory_command })
	mock:reply(3, report(true, { "New device" }), 0)
	equal(mock:device(1).label.string, "New device")
end)

test("lost power callback retries only on the next event at age 65", function()
	local mock = new_widget()
	mock.now = 1064
	mock:fire("routine")
	mock:expect_commands({ power_command })
	mock.now = 1065
	mock:expect_commands({ power_command })
	mock:fire("system_woke")
	mock:expect_commands({ power_command, power_command })
	mock:reply(1, "0", 0)
	equal(mock:status(), "Checking…")
	mock:fire("routine")
	mock:expect_commands({ power_command, power_command })
	mock:reply(2, "1", 0)
	mock:expect_commands({ power_command, power_command, power_command })
	mock:reply(3, "1", 0)
	equal(mock.widget.properties.icon.color, colors.white)
end)

test("opening after a lost power callback recovers with inventory; stale failure is ignored", function()
	local mock = new_widget()
	mock.now = 1065
	mock:fire("mouse.clicked")
	mock:expect_commands({ power_command, inventory_command })
	mock:reply(1, "", 1)
	mock:expect_commands({ power_command, inventory_command })
	mock:reply(2, report(true, { "Mouse" }), 0)
	equal(mock:status(), "1 connected")
end)

test("lost visible inventory recovers and ignores late reports", function()
	local mock = new_widget()
	mock:reply(1, "1", 0)
	mock:fire("mouse.clicked")
	mock.now = 1064
	mock:fire("routine")
	mock:expect_commands({ power_command, inventory_command })
	mock.now = 1065
	mock:fire("forced")
	mock:expect_commands({ power_command, inventory_command, inventory_command })
	mock:reply(3, report(true, { "Current device" }), 0)
	mock:reply(2, report(false), 0)
	equal(mock.widget.properties.icon.color, colors.white)
	equal(mock:status(), "1 connected")
	equal(mock:device(1).label.string, "Current device")
end)

test("lost fallback inventory recovers using current visibility and keeps the new guard", function()
	local mock = new_widget()
	mock:reply(1, "", 1)
	mock.now = 1065
	mock:fire("routine")
	mock:expect_commands({ power_command, inventory_command, power_command })
	mock:reply(2, report(false), 0)
	equal(mock:status(), "Checking…")
	mock:fire("forced")
	mock:expect_commands({ power_command, inventory_command, power_command })
	mock:reply(3, "1", 0)
	mock:reply(4, "1", 0)
	equal(mock.widget.properties.icon.color, colors.white)
end)

test("chained fallback inventory renews its own 65-second recovery deadline", function()
	local mock = new_widget()
	mock.now = 1059
	mock:reply(1, "", 1)
	mock:expect_commands({ power_command, inventory_command })
	mock.now = 1065
	mock:fire("routine")
	mock:expect_commands({ power_command, inventory_command })
	mock.now = 1123
	mock:fire("forced")
	mock:expect_commands({ power_command, inventory_command })
	mock.now = 1124
	mock:expect_commands({ power_command, inventory_command })
	mock:fire("system_woke")
	mock:expect_commands({ power_command, inventory_command, power_command })
	mock:reply(2, report(false), 0)
	equal(mock:status(), "Checking…")
	mock:reply(3, "1", 0)
	equal(mock.widget.properties.icon.color, colors.white)
end)

test("settings click behavior is unchanged and closes the popup", function()
	local mock = new_widget()
	mock:reply(1, "1", 0)
	mock:fire("mouse.clicked", { BUTTON = "right" })
	mock:expect_commands({ power_command, settings.commands.bluetooth })
	equal(mock.widget:query().popup.drawing, "off")
	mock:fire("mouse.clicked", { BUTTON = "left" })
	mock:reply(3, report(true), 0)
	mock.items["widgets.bluetooth.settings"].subscriptions["mouse.clicked"]()
	equal(mock.widget:query().popup.drawing, "off")
	mock:expect_commands({ power_command, settings.commands.bluetooth, inventory_command, settings.commands.bluetooth })
end)

print(string.format("Passed %d Bluetooth regression tests", passed))
