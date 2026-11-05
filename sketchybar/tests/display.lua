-- All desktop commands are mocked. Run: lua sketchybar/tests/display.lua
local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
package.path = root .. "/?.lua;" .. package.path
local settings = require("settings")
local colors = require("colors")
local first = "11111111-1111-1111-1111-111111111111"
local second = "22222222-2222-2222-2222-222222222222"
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
local function snapshot(mouse)
	return {
		ok = true,
		mouse_uuid = mouse or first,
		displays = {
			{
				uuid = first,
				name = "Built-in Display",
				brightness = 98.8,
				resolution = "1680x1050",
				refresh_rate = "60Hz",
			},
			{
				uuid = second,
				name = "Desk's $(touch /tmp/unwanted)",
				brightness = 50,
				resolution = "2560x1440",
				refresh_rate = "85.05Hz",
			},
		},
	}
end
local function fixture()
	local env = { items = {}, pending = {}, commands = {} }
	local sbar = {}
	function sbar.add(kind, name, third, fourth)
		local item = { name = name, kind = kind, properties = fourth or third, handlers = {} }
		function item:set(values)
			merge(self.properties, values)
		end
		function item:query()
			return { popup = { drawing = self.properties.popup and self.properties.popup.drawing and "on" or "off" } }
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
		env.commands[#env.commands + 1] = command
		if callback then
			env.pending[#env.pending + 1] = { command = command, callback = callback }
		end
	end
	function env:item(suffix)
		return self.items["widgets.display" .. (suffix and "." .. suffix or "")]
	end
	function env:fire(suffix, event, info)
		self:item(suffix).handlers[event or "mouse.clicked"](info or { BUTTON = "left" })
	end
	function env:take(pattern)
		for index, call in ipairs(self.pending) do
			if call.command:find(pattern, 1, true) then
				table.remove(self.pending, index)
				return call.callback, call.command
			end
		end
		error("Missing command: " .. pattern)
	end
	function env:open(result)
		self:fire()
		self:take(" snapshot")(result or snapshot(), 0)
	end
	package.loaded.sketchybar = sbar
	for _, name in ipairs({ "lib.popup", "lib.panel", "items.widgets.display" }) do
		package.loaded[name] = nil
	end
	require("items.widgets.display")
	return env
end
local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

test("collapsed bar performs no polling or hardware changes", function()
	local env = fixture()
	equal(#env.commands, 0)
	equal(env:item("timer").properties.update_freq, 0)
	env:fire(nil, "system_woke")
	equal(#env.commands, 0)
end)

test("open selects the display under the pointer and reads fractional brightness", function()
	local env = fixture()
	env:open(snapshot(second))
	equal(env:item("slider").properties.slider.percentage, 50)
	equal(env:item("device.2").properties.label.color, colors.accent)
	equal(env:item("mode").properties.label.string, "2560x1440 · 85.05Hz")
	equal(env:item("timer").properties.update_freq, 10)
	equal(#env.commands, 1)
end)

test("display picker changes target without changing hardware", function()
	local env = fixture()
	env:open()
	env:fire("device.2")
	equal(env:item("slider").properties.slider.percentage, 50)
	equal(#env.commands, 1)
	env:fire("preset.75")
	local _, command = env:take(" brightness ")
	assert(command:find("'" .. second .. "' 75", 1, true))
	assert(not command:find("touch", 1, true))
	equal(env:item("slider").properties.cursor, "default")
end)

test("slider rejects missing invalid nonfinite and out-of-range values", function()
	local env = fixture()
	env:open()
	for _, value in ipairs({ "bad", -1, 101, math.huge, 0 / 0 }) do
		env:fire("slider", "mouse.clicked", { PERCENTAGE = value })
	end
	env:fire("slider", "mouse.clicked", {})
	equal(#env.commands, 1)
	env:fire("slider", "mouse.clicked", { PERCENTAGE = "42.6" })
	local _, command = env:take(" brightness ")
	assert(command:find("'" .. first .. "' 43", 1, true))
end)

test("a mutation runs once and only verified readback updates brightness", function()
	local env = fixture()
	env:open()
	env:fire("preset.75")
	env:fire("preset.25")
	env:fire("device.2")
	env:fire("refresh")
	equal(#env.commands, 2)
	equal(env:item("slider").properties.slider.percentage, 98.8)
	env:take(" brightness ")({ ok = true, uuid = first, brightness = 75 }, 0)
	equal(env:item("slider").properties.slider.percentage, 75)
	equal(env:item("message").properties.drawing, false)
	equal(#env.commands, 2)
end)

test("failed and mismatched action results never claim success", function()
	for _, result in ipairs({
		{ ok = false },
		{ ok = true, uuid = second, brightness = 75 },
		{ ok = true, uuid = first },
	}) do
		local env = fixture()
		env:open()
		env:fire("preset.75")
		env:take(" brightness ")(result, result.ok and 0 or 1)
		equal(env:item("message").properties.label.color, colors.red)
		equal(env:item("slider").properties.slider.percentage, 98.8)
	end
end)

test("late inventory cannot overwrite an in-flight brightness change", function()
	local env = fixture()
	env:open()
	env:fire("timer", "routine")
	local old = env:take(" levels")
	env:fire("preset.75")
	old(snapshot(second), 0)
	equal(env:item("device.1").properties.label.color, colors.accent)
	equal(env:item("slider").properties.cursor, "default")
	env:take(" brightness ")({ ok = true, uuid = first, brightness = 75 }, 0)
	equal(env:item("slider").properties.slider.percentage, 75)
end)

test("closing stops polling and invalidates old inventory on reopen", function()
	local env = fixture()
	env:fire()
	local old = env:take(" snapshot")
	env:fire(nil, "mouse.exited.global")
	equal(env:item("timer").properties.update_freq, 0)
	env:open(snapshot(second))
	old(snapshot(first), 0)
	equal(env:item("device.2").properties.label.color, colors.accent)
	equal(env:item("slider").properties.slider.percentage, 50)
end)

test("unavailable brightness disables controls and unavailable backend recovers on refresh", function()
	local env = fixture()
	local data = snapshot()
	data.displays[1].brightness = nil
	env:open(data)
	equal(env:item("slider").properties.drawing, false)
	equal(env:item("preset.50").properties.cursor, "default")
	env:fire("preset.50")
	equal(#env.commands, 1)
	env:fire("refresh")
	env:take(" snapshot")({ ok = false }, 1)
	equal(env:item("device.1").properties.drawing, false)
	equal(env:item("message").properties.label.color, colors.red)
	env:fire("refresh")
	env:take(" snapshot")(snapshot(), 0)
	equal(env:item("slider").properties.cursor, "pointer")
end)

test("polling preserves selection and hotplug selects a remaining display", function()
	local env = fixture()
	env:open()
	env:fire("device.2")
	env:fire("timer", "routine")
	local data = snapshot(first)
	for _, device in ipairs(data.displays) do
		device.resolution, device.refresh_rate = nil, nil
	end
	env:take(" levels")(data, 0)
	equal(env:item("device.2").properties.label.color, colors.accent)
	equal(env:item("mode").properties.label.string, "2560x1440 · 85.05Hz")
	env:fire(nil, "display_change")
	data = snapshot(first)
	data.displays[2] = nil
	env:take(" snapshot")(data, 0)
	equal(env:item("slider").properties.slider.percentage, 98.8)
	equal(env:item("device.2").properties.drawing, false)
end)

test("invalid identifiers and corrupt brightness never become actions", function()
	local env = fixture()
	local data = snapshot()
	data.displays[1].uuid = "'$(touch /tmp/unwanted)'"
	data.displays[2].brightness = math.huge
	env:open(data)
	env:fire("preset.50")
	equal(#env.commands, 1)
	equal(env:item("device.1").properties.drawing, false)
end)

test("native shortcuts close the popup and BetterDisplay has a launch fallback", function()
	local env = fixture()
	env:open()
	env:fire(nil, "mouse.clicked", { BUTTON = "right" })
	equal(env.commands[#env.commands], settings.commands.display)
	equal(env:item():query().popup.drawing, "off")
	env:open()
	env:fire("betterdisplay")
	env:take(" --appMenu=on")("Failed", 1)
	equal(env.commands[#env.commands], "/usr/bin/open -a BetterDisplay")
end)

test("reopening keeps the last display frame until fresh inventory arrives", function()
	local env = fixture()
	env:open(snapshot(second))
	env:fire(nil, "mouse.exited.global")
	env:fire()
	equal(env:item("device.2").properties.drawing, true)
	equal(env:item("slider").properties.slider.percentage, 50)
	equal(env:item("mode").properties.label.string, "2560x1440 · 85.05Hz")
	equal(env:item("message").properties.drawing, false)
	env:take(" snapshot")(snapshot(first), 0)
	equal(env:item("device.2").properties.label.color, colors.accent)
end)

test("grid controls reuse panel dimensions and reset hover on close", function()
	local env = fixture()
	env:open()
	equal(env:item().properties.popup.columns, 4)
	equal(env:item("slider").properties.cell_span, 4)
	equal(env:item("slider").properties.align, "center")
	equal(env:item("slider").properties.icon.width, env:item("slider").properties.label.width)
	equal(env:item("heading").properties.label.font.size, 14)
	env:fire("preset.50", "mouse.entered")
	equal(env:item("preset.50").properties.background.color, colors.panel.hover)
	env:fire(nil, "mouse.exited.global")
	equal(env:item("preset.50").properties.background.color, colors.panel.control)
end)

print("PASS: " .. total .. " display panel tests")
