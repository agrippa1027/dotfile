-- Run with lua sketchybar/tests/volume.lua. All hardware commands are mocked.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. package.path
local colors = require("colors")
local utils = require("lib.utils")
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
	local env = { items = {}, commands = {}, pending = {} }
	local sbar = {}
	function sbar.add(kind, name, third, fourth)
		local properties = fourth or third
		local initial_background = {}
		merge(initial_background, properties.background or {})
		local item = {
			name = name,
			properties = properties,
			handlers = {},
			kind = kind,
			size = fourth and third,
			initial_background = initial_background,
		}
		function item:set(values)
			merge(self.properties, values)
		end
		function item:query()
			return { popup = { drawing = self.properties.popup and self.properties.popup.drawing and "on" or "off" } }
		end
		function item:subscribe(events, handler)
			for _, event in ipairs(type(events) == "table" and events or { events }) do
				self.handlers[event] = handler
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
		return self.items["widgets.volume" .. (suffix and "." .. suffix or "")]
	end
	function env:fire(suffix, event, info)
		self:item(suffix).handlers[event](info or { BUTTON = "left" })
	end
	function env:take(pattern)
		for index, call in ipairs(self.pending) do
			if call.command:find(pattern, 1, true) then
				table.remove(self.pending, index)
				return call.callback
			end
		end
		error("Missing command: " .. pattern)
	end
	function env:open(list, current)
		self:fire(nil, "mouse.clicked")
		self:take("output volume of")("37", 0)
		self:take(" -a -t output")(list or "Speakers\nHeadphones\n", 0)
		self:take(" -c -t output")(current or "Speakers\n", 0)
	end
	package.loaded.sketchybar = sbar
	package.loaded["lib.popup"] = nil
	package.loaded["lib.panel"] = nil
	package.loaded["items.widgets.volume"] = nil
	require("items.widgets.volume")
	return env
end

local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

test("left click opens a synced slider and places the active output first", function()
	local env = fixture()
	env:open()
	equal(env:item():query().popup.drawing, "on")
	equal(env:item("slider").kind, "slider")
	equal(env:item("slider").size, settings.popup.width - 80)
	equal(env:item("slider").properties.slider.percentage, 37)
	equal(env:item("output.1").properties.label.string, "Speakers")
	equal(env:item("output.1").properties.icon.color, colors.accent)
	equal(env:item("output.2").properties.label.string, "Headphones")
end)

test("audio hierarchy, slider and opaque card share panel geometry", function()
	local env = fixture()
	env:open()
	local card = env:item().properties.popup
	equal(card.background.color, colors.popup.bg)
	equal(card.background.border_color, colors.accent)
	equal(card.background.border_width, 2)
	equal(card.background.corner_radius, 4)
	local heading = env:item("heading").properties
	equal(heading.label.string, "Master volume · 37%")
	equal(heading.label.font.family, settings.font.text)
	equal(heading.label.font.size, 14)
	equal(heading.background.height, 42)
	local section = env:item("outputs").properties
	equal(section.label.font.size, 10)
	equal(section.label.color, colors.grey)
	equal(section.background.height, 28)
	for _, suffix in ipairs({ "slider", "output.1", "settings" }) do
		local props = env:item(suffix).properties
		equal(props.background.height, settings.popup.control_height)
		equal(props.background.corner_radius, 4)
		equal(props.background.border_width, 1)
	end
	equal(env:item("output.1").properties.label.font.family, settings.font.text)
	equal(env:item("output.1").properties.label.font.size, 12)
end)

test("every audio popup child keeps exact content width with explicit zero background padding", function()
	local env = fixture()
	local function check_layout()
		local children = 0
		for _, item in pairs(env.items) do
			local props = item.properties
			if props.position == "popup.widgets.volume" then
				children = children + 1
				equal(props.width, settings.popup.width)
				equal(item.initial_background.padding_left, 0)
				equal(item.initial_background.padding_right, 0)
				equal(props.background.padding_left, 0)
				equal(props.background.padding_right, 0)
			end
		end
		equal(children, 10)
	end
	check_layout()
	env:open()
	for _, suffix in ipairs({ "slider", "output.1", "output.2", "settings" }) do
		env:fire(suffix, "mouse.entered")
	end
	check_layout()
	env:fire(nil, "mouse.exited.global")
	check_layout()
end)

test("selected outputs restore their subtle tint after hover without recoloring text", function()
	local env = fixture()
	env:open()
	local selected = env:item("output.1").properties
	local other = env:item("output.2").properties
	equal(selected.background.color, colors.panel.selected)
	equal(other.background.color, colors.panel.control)
	for _, suffix in ipairs({ "output.1", "output.2", "slider", "settings" }) do
		env:fire(suffix, "mouse.entered")
		equal(env:item(suffix).properties.background.color, colors.panel.hover)
		equal(env:item(suffix).properties.background.border_color, colors.panel.hover_border)
		env:fire(suffix, "mouse.exited")
	end
	equal(selected.background.color, colors.panel.selected)
	equal(selected.background.border_color, colors.panel.control_border)
	equal(selected.icon.color, colors.accent)
	equal(selected.label.color, colors.white)
	equal(other.background.color, colors.panel.control)
	equal(other.label.color, colors.grey)
end)

test("dismissal resets hover and a refresh disables and clears hidden output selections", function()
	local env = fixture()
	env:open()
	for _, suffix in ipairs({ "output.1", "slider", "settings" }) do
		env:fire(suffix, "mouse.entered")
	end
	env:fire(nil, "mouse.exited.global")
	equal(env:item("output.1").properties.background.color, colors.panel.selected)
	equal(env:item("slider").properties.background.color, colors.panel.control)
	equal(env:item("settings").properties.background.color, colors.panel.control)
	env:fire(nil, "mouse.clicked")
	local output = env:item("output.1").properties
	equal(output.drawing, false)
	equal(output.background.color, colors.transparent)
	equal(output.background.border_width, 0)
	env:fire("output.1", "mouse.entered")
	equal(output.background.color, colors.transparent)
	equal(output.drawing, false)
	env:fire("output.1", "mouse.exited")
	env:take(" -a -t output")("Headphones\nSpeakers\n", 0)
	env:take(" -c -t output")("Headphones", 0)
	equal(output.drawing, true)
	equal(output.label.string, "Headphones")
	equal(output.background.color, colors.panel.selected)
	equal(env:item("output.2").properties.background.color, colors.panel.control)
end)

test("an unknown current output does not select empty slots", function()
	local env = fixture()
	env:fire(nil, "mouse.clicked")
	env:take(" -a -t output")("Speakers\n", 0)
	env:take(" -c -t output")("", 1)
	equal(env:item("output.1").properties.background.color, colors.panel.control)
	for index = 2, 6 do
		local props = env:item("output." .. index).properties
		equal(props.drawing, false)
		equal(props.background.color, colors.transparent)
		equal(props.background.border_width, 0)
	end
end)

test("volume events sync the bar and slider; invalid values are ignored", function()
	local env = fixture()
	env:fire(nil, "volume_change", { INFO = "45.6" })
	equal(env:item().properties.label.string, "46%")
	equal(env:item("heading").properties.label.string, "Master volume · 46%")
	for _, value in ipairs({ "garbage", -1, 101, math.huge, 0 / 0 }) do
		env:fire(nil, "volume_change", { INFO = value })
	end
	equal(env:item("slider").properties.slider.percentage, 46)
end)

test("a newer volume event prevents a stale forced read from replacing it", function()
	local env = fixture()
	env:fire(nil, "forced")
	local stale = env:take("output volume of")
	env:fire(nil, "volume_change", { INFO = 72 })
	stale("12", 0)
	equal(env:item().properties.label.string, "72%")
end)

test("slider validates and rounds percentage before issuing a command", function()
	local env = fixture()
	for _, value in ipairs({ "99; touch /tmp/unwanted", -1, 101, math.huge, 0 / 0 }) do
		env:fire("slider", "mouse.clicked", { PERCENTAGE = value })
	end
	equal(#env.commands, 0)
	env:fire("slider", "mouse.clicked", { PERCENTAGE = "58.8" })
	equal(env.commands[1], "osascript -e 'set volume output volume 59'")
	env:take("set volume")(nil, 0)
	env:take("output volume of")("59", 0)
	equal(env:item("slider").properties.slider.percentage, 59)
end)

test("scroll preserves fine control and rejects invalid deltas", function()
	local env = fixture()
	env:fire(nil, "mouse.scrolled", { INFO = { delta = 1, modifier = "ctrl" } })
	assert(env.commands[1]:find(" + 1)", 1, true))
	env:fire(nil, "mouse.scrolled", { INFO = { delta = 1 } })
	assert(env.commands[2]:find(" + 10", 1, true))
	for _, value in ipairs({ 0, math.huge, 0 / 0, "bad" }) do
		env:fire(nil, "mouse.scrolled", { INFO = { delta = value } })
	end
	equal(#env.commands, 2)
end)

test("device names are shell quoted and failed switches are reported", function()
	local env = fixture()
	local name = "Bob's $(touch /tmp/unwanted) `device`"
	env:open(name .. "\n", name)
	env:fire("output.1", "mouse.clicked")
	equal(
		env.commands[#env.commands],
		"/opt/homebrew/bin/SwitchAudioSource -t output -s " .. utils.quote(name) .. " 2>/dev/null"
	)
	env:take(" -s ")("", 1)
	equal(env:item("outputs").properties.label.string, "SWITCH FAILED · USE SETTINGS")
end)

test("failed output reads hide stale choices and offer settings", function()
	local env = fixture()
	env:open()
	env:fire(nil, "mouse.clicked")
	env:fire(nil, "mouse.clicked")
	env:take(" -a -t output")("", 1)
	equal(env:item("output.1").properties.drawing, false)
	equal(env:item("outputs").properties.label.string, "OUTPUTS UNAVAILABLE · USE SETTINGS")
	local count = #env.commands
	env:fire("output.1", "mouse.clicked")
	equal(#env.commands, count)
end)

test("closing and reopening discards old list and current-device callbacks", function()
	local env = fixture()
	env:fire(nil, "mouse.clicked")
	env:take(" -a -t output")("Old\n", 0)
	local stale_current = env:take(" -c -t output")
	env:fire(nil, "mouse.clicked")
	env:fire(nil, "mouse.clicked")
	local current_list = env:take(" -a -t output")
	stale_current("Old", 0)
	equal(env:item("output.1").properties.drawing, false)
	current_list("New\n", 0)
	env:take(" -c -t output")("New", 0)
	equal(env:item("output.1").properties.label.string, "New")
end)

test("list caps at six outputs, deduplicates, and keeps the current device", function()
	local env = fixture()
	env:open("A\nB\nC\nD\nE\nF\nG\nG\n", "G")
	equal(env:item("output.1").properties.label.string, "G")
	equal(env:item("output.6").properties.label.string, "E")
	equal(env:item("outputs").properties.label.string, "OUTPUT DEVICES · MORE IN SETTINGS")
end)

test("right click and footer open settings; footer dismisses the popup", function()
	local env = fixture()
	env:fire(nil, "mouse.clicked", { BUTTON = "right" })
	equal(env.commands[1], settings.commands.sound)
	env:open()
	env:fire("settings", "mouse.clicked")
	equal(env.commands[#env.commands], settings.commands.sound)
	equal(env:item():query().popup.drawing, "off")
end)

print("PASS: " .. total .. " audio regression tests")
