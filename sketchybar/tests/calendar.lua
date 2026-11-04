-- Run with lua path/to/sketchybar/tests/calendar.lua from any directory.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. package.path
local calendar = require("lib.calendar")
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
local items, commands = {}, {}
local sbar = {}
function sbar.add(_, name, config)
	local item = { name = name, config = config, properties = config, handlers = {} }
	function item:set(values)
		for key, value in pairs(values) do
			if type(value) == "table" and type(self.properties[key]) == "table" then
				for field, setting in pairs(value) do
					self.properties[key][field] = setting
				end
			elseif (key == "icon" or key == "label") and type(value) == "string" then
				self.properties[key].string = value
			else
				self.properties[key] = value
			end
		end
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
	return item
end
function sbar.exec(command)
	commands[#commands + 1] = command
end
package.loaded.sketchybar = sbar
package.loaded["lib.popup"] = nil
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
	assert(items["calendar.week.2"].properties.label.string:find("[04]", 1, true))
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
print("PASS: " .. total .. " calendar tests")
