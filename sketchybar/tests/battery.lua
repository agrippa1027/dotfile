-- Run with lua sketchybar/tests/battery.lua. All commands are mocked.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. package.path
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local total = 0

local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function merge(target, values)
	for key, value in pairs(values) do
		if type(value) == "table" then
			target[key] = type(target[key]) == "table" and target[key] or {}
			merge(target[key], value)
		elseif (key == "label" or key == "icon") and type(value) == "string" then
			target[key] = target[key] or {}
			target[key].string = value
		else
			target[key] = value
		end
	end
end

local function fixture()
	local env = { items = {}, defaults = {}, commands = {}, pending = {} }
	local sbar = {}
	function sbar.default(values)
		merge(env.defaults, values)
	end
	function sbar.add(_, name, values)
		local initial_background = {}
		merge(initial_background, values.background or {})
		local item = { name = name, properties = {}, handlers = {}, initial_background = initial_background }
		merge(item.properties, env.defaults)
		merge(item.properties, values)
		function item:set(properties)
			merge(self.properties, properties)
		end
		function item:query()
			return { popup = { drawing = self.properties.popup.drawing and "on" or "off" } }
		end
		function item:subscribe(events, callback)
			for _, event in ipairs(type(events) == "table" and events or { events }) do
				self.handlers[event] = callback
			end
		end
		env.items[name] = item
		return item
	end
	function sbar.exec(command, callback)
		assert(command == "pmset -g batt" or command == settings.commands.battery, "Unexpected command: " .. command)
		env.commands[#env.commands + 1] = command
		if callback then
			env.pending[#env.pending + 1] = callback
		end
	end
	function env:item(suffix)
		return self.items["widgets.battery" .. (suffix and "." .. suffix or "")]
	end
	function env:fire(suffix, event, info)
		assert(self:item(suffix).handlers[event], "Missing event: " .. event)(info or { BUTTON = "left" })
	end
	function env:take()
		return assert(table.remove(self.pending, 1), "Missing pmset callback")
	end
	function env:update(result, status, event)
		self:fire(nil, event or "forced")
		self:take()(result, status)
	end
	function env:value(suffix)
		return self:item(suffix).properties.label.string
	end
	package.loaded.sketchybar = sbar
	for _, module in ipairs({ "default", "lib.popup", "lib.panel", "items.widgets.battery" }) do
		package.loaded[module] = nil
	end
	require("default")
	require("items.widgets.battery")
	return env
end

local function report(source, charge, state, estimate)
	return string.format(
		"Now drawing from '%s'\n -InternalBattery-0 (id=12345)\t%s%%; %s; %s present: true\n",
		source,
		charge,
		state,
		estimate or "(no estimate)"
	)
end

local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

test("Power card inherits shared styling and preserves the bar geometry", function()
	local env = fixture()
	local bar = env:item().properties
	equal(bar.position, "right")
	equal(bar.update_freq, 180)
	equal(bar.icon.font.size, 19)
	equal(bar.icon.font.style, settings.font.style_map.Regular)
	equal(bar.popup.height, settings.popup.height)
	equal(bar.popup.background.color, colors.popup.bg)
	equal(bar.popup.background.border_color, colors.accent)
	equal(bar.popup.background.border_width, 2)
	equal(bar.popup.background.corner_radius, 4)
	equal(bar.popup.blur_radius, 0)
	local heading = env:item("heading").properties
	equal(heading.label.string, "Power")
	equal(heading.label.font.family, settings.font.text)
	equal(heading.label.font.size, 14)
	equal(heading.background.height, 42)
	for _, name in ipairs({ "source", "status", "remaining" }) do
		local row = env:item(name).properties
		equal(row.width, settings.popup.width)
		equal(row.icon.align, "left")
		equal(row.icon.width, 116)
		equal(row.icon.color, colors.grey)
		equal(row.icon.font.family, settings.font.text)
		equal(row.icon.font.size, 10)
		equal(row.label.align, "right")
		equal(row.label.width, settings.popup.width - 136)
		equal(row.label.font.family, settings.font.text)
		equal(row.label.font.size, 12)
		equal(row.label.color, colors.white)
	end
	equal(#env.commands, 0)
end)

test("all Power popup children explicitly use zero background padding and exact content widths", function()
	local env = fixture()
	local function check_layout()
		local children = 0
		for _, item in pairs(env.items) do
			local props = item.properties
			if props.position == "popup.widgets.battery" then
				children = children + 1
				equal(props.width, settings.popup.width)
				equal(item.initial_background.padding_left, 0)
				equal(item.initial_background.padding_right, 0)
				equal(props.background.padding_left, 0)
				equal(props.background.padding_right, 0)
			end
		end
		equal(children, 5)
	end
	check_layout()
	env:fire(nil, "mouse.clicked")
	env:take()(report("AC Power", 42, "charging", "1:05 remaining"), 0)
	env:fire("settings", "mouse.entered")
	check_layout()
	env:fire(nil, "mouse.exited.global")
	check_layout()
end)

test("on-battery reads show source, state and the reported remaining time", function()
	local env = fixture()
	env:update(report("Battery Power", 75, "discharging", "2:30 remaining"), 0)
	equal(env:value(), "75%")
	equal(env:item().properties.icon.string, icons.battery._75)
	equal(env:value("source"), "Battery Power")
	equal(env:value("status"), "On battery")
	equal(env:item("remaining").properties.icon.string, "TIME REMAINING")
	equal(env:value("remaining"), "2:30h")
end)

test("charging uses time-to-full caption and preserves the AC bar glyph", function()
	local env = fixture()
	env:update(report("AC Power", 42, "charging", "1:05 remaining"), 0)
	equal(env:value(), "42%")
	equal(env:item().properties.icon.string, icons.battery.charging)
	equal(env:item().properties.icon.color, colors.green)
	equal(env:value("source"), "AC Power")
	equal(env:value("status"), "Charging")
	equal(env:item("remaining").properties.icon.string, "TIME TO FULL")
	equal(env:value("remaining"), "1:05h")
end)

test("fully charged AC is distinct from charging and does not offer a zero-time estimate", function()
	local env = fixture()
	env:update(report("AC Power", 100, "charged", "0:00 remaining"), 0)
	equal(env:value(), "100%")
	equal(env:item().properties.icon.string, icons.battery.charging)
	equal(env:value("status"), "Fully charged")
	equal(env:item("remaining").properties.icon.string, "ESTIMATE")
	equal(env:value("remaining"), "Not needed")
	env:update(report("Battery Power", 100, "charged"), 0)
	equal(env:value("status"), "On battery")
	equal(env:item().properties.icon.string, icons.battery._100)
	equal(env:value("remaining"), "No estimate")
end)

test("paused AC charging is not confused with charging or full", function()
	local env = fixture()
	for _, state in ipairs({ "not charging", "not charging present: true", "AC attached" }) do
		env:update(report("AC Power", 80, state, "0:00 remaining"), 0)
		equal(env:value("status"), "Not charging")
		equal(env:value("remaining"), "No estimate")
		equal(env:item("remaining").properties.icon.string, "ESTIMATE")
		equal(env:item().properties.icon.string, icons.battery.charging)
	end
end)

test("finishing charge and AC discharging keep accurate estimate captions", function()
	local env = fixture()
	env:update(report("AC Power", 99, "finishing charge"), 0)
	equal(env:value("status"), "Charging")
	equal(env:item("remaining").properties.icon.string, "TIME TO FULL")
	equal(env:value("remaining"), "No estimate")
	env:update(report("AC Power", 35, "discharging", "0:45 remaining"), 0)
	equal(env:value("status"), "Discharging")
	equal(env:item("remaining").properties.icon.string, "TIME REMAINING")
	equal(env:value("remaining"), "0:45h")
end)

test("missing and malformed estimates never invent a duration", function()
	local env = fixture()
	for _, source in ipairs({ "AC Power", "Battery Power" }) do
		local state = source == "AC Power" and "charging" or "discharging"
		for _, estimate in ipairs({
			"(no estimate)",
			"(no estimate yet)",
			"1:60 remaining",
			"1:5 remaining",
			"-1:30 remaining",
			"unknown",
		}) do
			env:update(report(source, 50, state, estimate), 0)
			equal(env:value("remaining"), "No estimate")
		end
	end
end)

test("bar thresholds, warning colors and leading-zero percentages are unchanged", function()
	local env = fixture()
	for _, case in ipairs({
		{ 100, icons.battery._100, colors.green },
		{ 81, icons.battery._100, colors.green },
		{ 80, icons.battery._75, colors.green },
		{ 61, icons.battery._75, colors.green },
		{ 60, icons.battery._50, colors.green },
		{ 41, icons.battery._50, colors.green },
		{ 40, icons.battery._25, colors.orange },
		{ 21, icons.battery._25, colors.orange },
		{ 20, icons.battery._0, colors.red },
		{ 9, icons.battery._0, colors.red },
		{ 0, icons.battery._0, colors.red },
	}) do
		env:update(report("Battery Power", case[1], "discharging"), 0)
		equal(env:value(), string.format("%02d%%", case[1]))
		equal(env:item().properties.icon.string, case[2])
		equal(env:item().properties.icon.color, case[3])
	end
	env:update(report("AC Power", 5, "charging"), 0)
	equal(env:value(), "05%")
	equal(env:item().properties.icon.string, icons.battery.charging)
	equal(env:item().properties.icon.color, colors.green)
end)

test("missing, failed and invalid results clear stale readouts without throwing", function()
	local env = fixture()
	for _, case in ipairs({
		{ status = 0 },
		{ result = {}, status = 0 },
		{ result = false, status = 0 },
		{ result = "", status = 0 },
		{ result = "pmset failed", status = 1 },
		{ result = report("AC Power", 42, "charging"), status = 1 },
		{ result = report("AC Power", 42, "charging") },
		{ result = "Now drawing from 'AC Power'\n", status = 0 },
		{ result = report("Unknown", 42, "discharging"), status = 0 },
		{ result = report("Battery Power", 101, "discharging"), status = 0 },
		{ result = report("Battery Power", -5, "discharging"), status = 0 },
	}) do
		env:update(report("AC Power", 42, "charging", "1:05 remaining"), 0)
		env:update(case.result, case.status)
		equal(env:value(), "?")
		equal(env:item().properties.icon.string, "!")
		equal(env:item().properties.icon.color, colors.grey)
		equal(env:value("source"), "Unavailable")
		equal(env:value("status"), "Unavailable")
		equal(env:value("remaining"), "No estimate")
		equal(env:item("remaining").properties.icon.string, "ESTIMATE")
	end
end)

test("an unknown AC state does not invent charging or a time estimate", function()
	local env = fixture()
	env:update(report("AC Power", 50, "unknown", "1:00 remaining"), 0)
	equal(env:value(), "50%")
	equal(env:value("source"), "AC Power")
	equal(env:value("status"), "Unavailable")
	equal(env:value("remaining"), "No estimate")
end)

test("all existing refresh events remain read-only and sync the popup", function()
	local env = fixture()
	for _, event in ipairs({ "forced", "routine", "power_source_change", "system_woke" }) do
		env:update(report("Battery Power", 55, "discharging", "3:20 remaining"), 0, event)
		equal(env.commands[#env.commands], "pmset -g batt")
		equal(env:value(), "55%")
		equal(env:value("remaining"), "3:20h")
	end
	equal(#env.commands, 4)
end)

test("newer requests prevent stale pmset callbacks from replacing the current state", function()
	local env = fixture()
	env:fire(nil, "forced")
	local stale = env:take()
	env:fire(nil, "power_source_change")
	env:take()(report("AC Power", 65, "charging", "0:50 remaining"), 0)
	stale(report("Battery Power", 10, "discharging", "0:20 remaining"), 0)
	equal(env:value(), "65%")
	equal(env:value("status"), "Charging")
	equal(env:value("remaining"), "0:50h")
end)

test("left click and named toggle refresh the popup and highlight its owner", function()
	local env = fixture()
	env:fire(nil, "mouse.clicked")
	equal(env:item():query().popup.drawing, "on")
	equal(env:item().properties.background.color, colors.panel.selected)
	equal(env.commands[1], "pmset -g batt")
	env:take()(report("Battery Power", 75, "discharging"), 0)
	env:fire(nil, "mouse.exited.global")
	equal(env:item():query().popup.drawing, "off")
	equal(env:item().properties.background.color, colors.transparent)
	local popup = require("lib.popup")
	equal(popup.toggle("widgets.battery"), true)
	equal(env:item():query().popup.drawing, "on")
	equal(#env.commands, 2)
	popup.close_all()
	equal(env:item():query().popup.drawing, "off")
end)

test("Battery Settings action has shared hover geometry and resets on close", function()
	local env = fixture()
	env:fire(nil, "mouse.clicked")
	local action = env:item("settings").properties
	equal(action.label.string, "Battery Settings  ↗")
	equal(action.background.height, settings.popup.control_height)
	equal(action.background.corner_radius, 4)
	equal(action.background.border_width, 1)
	equal(action.background.color, colors.panel.control)
	env:fire("settings", "mouse.entered")
	equal(action.background.color, colors.panel.hover)
	equal(action.background.border_color, colors.panel.hover_border)
	equal(action.label.color, colors.blue)
	env:fire("settings", "mouse.exited")
	equal(action.background.color, colors.panel.control)
	equal(action.background.border_color, colors.panel.control_border)
	env:fire("settings", "mouse.entered")
	env:fire(nil, "mouse.exited.global")
	equal(action.background.color, colors.panel.control)
	env:fire(nil, "mouse.clicked")
	equal(action.background.color, colors.panel.control)
end)

test("right click preserves settings behavior and the new footer closes before opening settings", function()
	local env = fixture()
	env:fire(nil, "mouse.clicked", { BUTTON = "right" })
	equal(env.commands[1], settings.commands.battery)
	equal(env:item():query().popup.drawing, "off")
	env:fire(nil, "mouse.clicked")
	env:take()(report("AC Power", 100, "charged"), 0)
	env:fire("settings", "mouse.entered")
	env:fire("settings", "mouse.clicked")
	equal(env.commands[#env.commands], settings.commands.battery)
	equal(env:item():query().popup.drawing, "off")
	equal(env:item().properties.background.color, colors.transparent)
	equal(env:item("settings").properties.background.color, colors.panel.control)
	equal(env:value(), "100%")
end)

print("PASS: " .. total .. " battery tests")
