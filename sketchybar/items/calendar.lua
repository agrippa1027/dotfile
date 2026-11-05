local sbar = require("sketchybar")
local settings = require("settings")
local colors = require("colors")
local calendar = require("lib.calendar")
local popup = require("lib.popup")
local panel = require("lib.panel")

local cal = sbar.add("item", "calendar", {
	icon = {
		color = colors.grey,
		padding_left = 8,
		font = {
			family = settings.font.text,
			style = settings.font.style_map.Regular,
			size = 14.0,
		},
	},
	label = {
		color = colors.white,
		padding_right = 8,
		width = 49,
		align = "right",
		font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 14 },
	},

	position = "center",
	update_freq = 30,
	padding_left = 1,
	padding_right = 1,

	background = {
		color = colors.transparent,
	},
	popup = {
		align = "center",
		height = settings.popup.height,
		columns = 8,
		blur_radius = 0,
		background = {
			color = colors.popup.bg,
			border_color = colors.accent,
			border_width = settings.popup.border_width,
			corner_radius = settings.popup.corner_radius,
		},
	},
})

local gap = settings.popup.gap or 0
local cell_width = math.floor((settings.popup.width - 7 * gap) / 8)
local width = cell_width * 8 + 7 * gap
local actions = {}
local function row(name, label, span, color)
	span = span or 8
	local row_width = span == 8 and width or cell_width * span + (span - 1) * gap
	return sbar.add("item", "calendar." .. name, {
		position = "popup." .. cal.name,
		width = row_width,
		cell_span = span,
		padding_left = 0,
		padding_right = 0,
		align = "center",
		icon = { drawing = false },
		label = {
			string = label,
			color = color or colors.white,
			align = "center",
			width = row_width,
			padding_left = 0,
			padding_right = 0,
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 12 },
		},
		background = { height = settings.popup.height, color = colors.transparent, padding_left = 0, padding_right = 0 },
	})
end
local function action(item)
	actions[#actions + 1] = panel.action(item)
	return item
end
local function reset_hover()
	for _, state in ipairs(actions) do
		state:reset()
	end
end

local previous = action(row("previous", "‹", 1, colors.grey))
local heading = row("heading", "", 6)
panel.heading(heading)
local next_month = action(row("next", "›", 1, colors.grey))
for index, label in ipairs({ "Wk", "Mo", "Tu", "We", "Th", "Fr", "Sa", "Su" }) do
	panel.section(row("weekdays." .. index, label, 1))
end
local weeks = {}
for index = 1, 6 do
	local week = { number = row("week." .. index, "", 1, colors.grey), days = {} }
	panel.section(week.number)
	for weekday = 1, 7 do
		week.days[weekday] = row("day." .. index .. "." .. weekday, "", 1)
	end
	weeks[index] = week
end
local today_row = action(row("today", "Today", 8, colors.accent))
local open_calendar = action(row("open", "Open Calendar  ↗", 8, colors.blue))

local viewed = os.date("*t")
local rendered_month
local function render()
	local key = string.format("%d-%d-%s", viewed.year, viewed.month, os.date("%Y-%m-%d"))
	if rendered_month == key then
		return
	end
	local month = calendar.month(viewed.year, viewed.month)
	viewed.year, viewed.month = month.year, month.month
	rendered_month = string.format("%d-%d-%s", viewed.year, viewed.month, os.date("%Y-%m-%d"))
	heading:set({ label = month.title })
	for index, week in ipairs(month.weeks) do
		local contains_days = false
		for _, day in ipairs(week.days) do
			contains_days = contains_days or day.in_month
		end
		weeks[index].number:set({ drawing = contains_days, label = week.number })
		for weekday, day in ipairs(week.days) do
			local current = day.in_month and day.today
			weeks[index].days[weekday]:set({
				drawing = contains_days,
				label = {
					string = string.format("%02d", day.day),
					color = current and colors.accent
						or not day.in_month and colors.panel.control_border
						or weekday >= 6 and colors.grey
						or colors.white,
				},
				background = {
					height = settings.popup.control_height,
					corner_radius = settings.popup.corner_radius,
					padding_left = 0,
					padding_right = 0,
					color = current and colors.panel.selected or colors.transparent,
					border_width = current and 1 or 0,
					border_color = colors.accent,
				},
			})
		end
	end
	today_row:set({ label = os.date("Today · %a, %d %b") })
end

local function reset()
	viewed = os.date("*t")
	render()
end

local function step(delta)
	viewed.month = viewed.month + delta
	render()
end

cal:subscribe({ "forced", "routine", "system_woke" }, function()
	cal:set({ icon = os.date("%a. %d %b."), label = os.date("%H:%M") })
	if popup.is_open(cal) then
		render()
	end
end)

local details = popup.bind(cal, {
	settings_command = "open -a 'Calendar'",
	on_open = function()
		reset_hover()
		reset()
	end,
	on_close = reset_hover,
})
previous:subscribe("mouse.clicked", function()
	step(-1)
end)
next_month:subscribe("mouse.clicked", function()
	step(1)
end)
today_row:subscribe("mouse.clicked", reset)
cal:subscribe("mouse.scrolled", function(env)
	local delta = type(env.INFO) == "table" and tonumber(env.INFO.delta)
	if delta and delta ~= 0 then
		step(delta > 0 and -1 or 1)
	end
end)
open_calendar:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec("open -a 'Calendar'")
end)

return cal
