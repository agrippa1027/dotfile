-- Run with lua path/to/sketchybar/tests/calendar.lua from any directory.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. package.path
local calendar = require("lib.calendar")
local colors = require("colors")
local shared_settings = require("settings")
local settings = setmetatable({
	popup = setmetatable({ gap = 6 }, { __index = shared_settings.popup }),
}, { __index = shared_settings })
package.loaded.settings = settings
local total = 0
local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

test("Monday-first month includes ISO week from preceding year", function()
	local january = calendar.month(2021, 1, { year = 2021, month = 1, day = 1 })
	equal(january.weeks[1].number, "53")
	equal(january.weeks[1].days[1].day, 28)
	equal(january.weeks[1].days[1].in_month, false)
	equal(january.weeks[1].days[5].day, 1)
	equal(january.weeks[1].days[5].today, true)
	equal(january.weeks[2].number, "01")
end)

test("month stepping normalizes December and January across years", function()
	local january = calendar.month(2026, 13)
	equal(january.year, 2027)
	equal(january.month, 1)
	local december = calendar.month(2026, 0)
	equal(december.year, 2025)
	equal(december.month, 12)
end)

test("leap day follows Gregorian century rules", function()
	for _, case in ipairs({ { 2024, 29 }, { 2025, 28 }, { 2000, 29 }, { 2100, 28 } }) do
		local count = 0
		for _, week in ipairs(calendar.month(case[1], 2).weeks) do
			for _, day in ipairs(week.days) do
				count = count + (day.in_month and 1 or 0)
			end
		end
		equal(count, case[2])
	end
end)

test("six-week month retains final Sunday", function()
	local august = calendar.month(2021, 8)
	equal(august.weeks[1].days[7].day, 1)
	equal(august.weeks[6].days[2].day, 31)
	equal(august.weeks[6].days[2].in_month, true)
end)

test("every date remains consecutive through DST transition months", function()
	for _, month in ipairs({ 3, 11 }) do
		local expected = 1
		for _, week in ipairs(calendar.month(2026, month).weeks) do
			for _, day in ipairs(week.days) do
				if day.in_month then
					equal(day.day, expected)
					expected = expected + 1
				end
			end
		end
		equal(expected, month == 3 and 32 or 31)
	end
end)

local real_date = os.date
local fixed = os.time({ year = 2026, month = 11, day = 4, hour = 12 })
---@diagnostic disable-next-line: duplicate-set-field
os.date = function(format, timestamp)
	return real_date(format, timestamp or fixed)
end
local items, commands, order = {}, {}, {}
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
local sbar = {}
function sbar.add(_, name, config)
	local initial_background = {}
	merge(initial_background, config.background or {})
	local item =
		{ name = name, config = config, properties = config, handlers = {}, initial_background = initial_background }
	function item:set(values)
		merge(self.properties, values)
	end
	function item:query()
		return { popup = { drawing = self.properties.popup.drawing and "on" or "off" } }
	end
	function item:subscribe(events, callback)
		for _, event in ipairs(type(events) == "table" and events or { events }) do
			self.handlers[event] = callback
		end
	end
	items[name] = item
	order[#order + 1] = item
	return item
end
function sbar.exec(command)
	commands[#commands + 1] = command
end
package.loaded.sketchybar = sbar
package.loaded["lib.popup"] = nil
package.loaded["lib.panel"] = nil
package.loaded["items.calendar"] = nil
local cal = require("items.calendar")
local function click(name, button)
	items[name].handlers["mouse.clicked"]({ BUTTON = button or "left" })
end
local function title()
	return items["calendar.heading"].properties.label.string
end

test("clock keeps its center position and opens current month popup", function()
	equal(cal.config.position, "center")
	equal(cal.config.click_script, nil)
	click("calendar")
	equal(cal:query().popup.drawing, "on")
	equal(title(), "November 2026")
	equal(items["calendar.day.2.3"].properties.label.string, "04")
	equal(items["calendar.day.2.3"].properties.background.color, colors.panel.selected)
end)

test("clock is quiet mono and the popup uses the opaque theme frame", function()
	cal.handlers.routine()
	equal(cal.properties.icon.color, colors.grey)
	equal(cal.properties.icon.font.family, settings.font.text)
	equal(cal.properties.icon.font.style, settings.font.style_map.Regular)
	equal(cal.properties.label.color, colors.white)
	equal(cal.properties.label.font.size, 12)
	equal(cal.properties.popup.height, settings.popup.height)
	equal(cal.properties.popup.background.color, colors.popup.bg)
	equal(cal.properties.popup.background.border_color, colors.accent)
	equal(cal.properties.popup.background.border_width, 2)
	equal(cal.properties.popup.background.corner_radius, 4)
end)

test("eight-column grid aligns compact navigation, captions and full-width actions", function()
	equal(cal.properties.popup.columns, 8)
	equal(order[2].name, "calendar.previous")
	equal(order[3].name, "calendar.heading")
	equal(order[4].name, "calendar.next")
	local heading = items["calendar.heading"].properties
	equal(heading.cell_span, 6)
	equal(heading.background.height, 42)
	equal(heading.label.font.size, 14)
	equal(heading.label.font.family, settings.font.text)
	local gap = settings.popup.gap
	local cell_width = math.floor((settings.popup.width - 7 * gap) / 8)
	local grid_width = cell_width * 8 + 7 * gap
	equal(cell_width, 34)
	equal(grid_width, 314)
	local children = 0
	for _, item in ipairs(order) do
		local props = item.properties
		if props.position == "popup.calendar" then
			children = children + 1
			local expected_width = cell_width * props.cell_span + (props.cell_span - 1) * gap
			equal(props.width, expected_width)
			equal(props.width % 1, 0)
			equal(props.label.width, expected_width)
			equal(props.padding_left, 0)
			equal(props.padding_right, 0)
			equal(item.initial_background.padding_left, 0)
			equal(item.initial_background.padding_right, 0)
			equal(props.background.padding_left, 0)
			equal(props.background.padding_right, 0)
		end
	end
	equal(children, 61)
	equal(
		items["calendar.previous"].properties.width + heading.width + items["calendar.next"].properties.width + 2 * gap,
		grid_width
	)
	equal(items["calendar.today"].properties.width, grid_width)
	equal(items["calendar.open"].properties.width, grid_width)
	for week = 1, 6 do
		local row_width = items["calendar.week." .. week].properties.width
		for weekday = 1, 7 do
			row_width = row_width + gap + items["calendar.day." .. week .. "." .. weekday].properties.width
		end
		equal(row_width, grid_width)
	end
	for index, label in ipairs({ "Wk", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) do
		local caption = items["calendar.weekdays." .. index].properties
		equal(caption.label.string, label)
		equal(caption.label.font.size, 10)
		equal(caption.background.height, 28)
	end
	equal(items["calendar.today"].properties.cell_span, 8)
	equal(items["calendar.open"].properties.cell_span, 8)
end)

test("today alone is highlighted while weekends and adjacent-month dates are muted", function()
	local highlights = 0
	for week = 1, 6 do
		for weekday = 1, 7 do
			local props = items["calendar.day." .. week .. "." .. weekday].properties
			equal(props.label.font.size, 12)
			if props.background.border_width == 1 then
				highlights = highlights + 1
				equal(props.label.string, "04")
				equal(props.label.color, colors.accent)
				equal(props.background.corner_radius, 4)
				equal(props.background.height, settings.popup.control_height)
				equal(props.background.border_color, colors.accent)
			end
		end
	end
	equal(highlights, 1)
	equal(items["calendar.day.2.2"].properties.label.color, colors.white)
	equal(items["calendar.day.2.6"].properties.label.color, colors.grey)
	equal(items["calendar.day.1.1"].properties.label.string, "26")
	equal(items["calendar.day.1.1"].properties.label.color, colors.panel.control_border)
	equal(items["calendar.week.1"].properties.label.string, "44")
end)

test("navigation crosses year, Today resets, and scroll moves month", function()
	click("calendar.next")
	equal(title(), "December 2026")
	click("calendar.next")
	equal(title(), "January 2027")
	click("calendar.previous")
	equal(title(), "December 2026")
	click("calendar.today")
	equal(title(), "November 2026")
	cal.handlers["mouse.scrolled"]({ INFO = { delta = 1 } })
	equal(title(), "October 2026")
	cal.handlers["mouse.scrolled"]({ INFO = { delta = -1 } })
	equal(title(), "November 2026")
end)

test("empty week rows hide as complete grid rows and clear the previous today highlight", function()
	for _ = 1, 3 do
		click("calendar.next")
	end
	equal(title(), "February 2027")
	for week = 1, 6 do
		local visible = week <= 4
		equal(items["calendar.week." .. week].properties.drawing, visible)
		for weekday = 1, 7 do
			local props = items["calendar.day." .. week .. "." .. weekday].properties
			equal(props.drawing, visible)
			equal(props.background.border_width, 0)
			equal(props.background.color, colors.transparent)
			equal(props.background.padding_left, 0)
			equal(props.background.padding_right, 0)
		end
	end
	click("calendar.today")
end)

test("action hover preserves text and resets on exit and popup dismissal", function()
	for _, name in ipairs({ "previous", "next", "today", "open" }) do
		local item = items["calendar." .. name]
		local color = item.properties.label.color
		equal(item.properties.background.height, settings.popup.control_height)
		equal(item.properties.background.corner_radius, 4)
		item.handlers["mouse.entered"]()
		equal(item.properties.background.padding_left, 0)
		equal(item.properties.background.padding_right, 0)
		equal(item.properties.background.color, colors.panel.hover)
		equal(item.properties.background.border_color, colors.panel.hover_border)
		equal(item.properties.label.color, color)
		item.handlers["mouse.exited"]()
		equal(item.properties.background.color, colors.panel.control)
		equal(item.properties.background.border_width, 1)
		item.handlers["mouse.entered"]()
	end
	cal.handlers["mouse.exited.global"]()
	for _, name in ipairs({ "previous", "next", "today", "open" }) do
		equal(items["calendar." .. name].properties.background.color, colors.panel.control)
	end
	click("calendar")
end)

test("outside exit closes and reopening resets browsed month", function()
	click("calendar.next")
	cal.handlers["mouse.exited.global"]()
	equal(cal:query().popup.drawing, "off")
	click("calendar")
	equal(title(), "November 2026")
end)

test("right click and Calendar footer launch native app", function()
	click("calendar", "right")
	equal(commands[#commands], "open -a 'Calendar'")
	click("calendar.open")
	equal(commands[#commands], "open -a 'Calendar'")
	equal(cal:query().popup.drawing, "off")
end)

os.date = real_date
package.loaded.settings = shared_settings
print("PASS: " .. total .. " calendar tests")
