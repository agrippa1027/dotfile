local sbar = require("sketchybar")
local settings = require("settings")
local colors = require("colors")
local calendar = require("lib.calendar")
local popup = require("lib.popup")

local cal = sbar.add("item", "calendar", {
	icon = {
		color = colors.red,
		padding_left = 8,
		font = {
			family = settings.font.text,
			style = settings.font.style_map["Black"],
			size = 12.0,
		},
	},
	label = {
		color = colors.white,
		padding_right = 8,
		width = 49,
		align = "right",
		font = { family = settings.font.text },
	},

	position = "center",
	update_freq = 30,
	padding_left = 1,
	padding_right = 1,

	background = {
		color = colors.transparent,
	},
	popup = { align = "center", height = 26 },
})

local width = settings.popup.width
local function row(name, label, options)
	options = options or {}
	options.position = "popup." .. cal.name
	options.width = width
	options.align = "center"
	options.icon = options.icon or { drawing = false }
	options.label = options.label or { string = label, color = colors.white, align = "center", width = width - 20 }
	return sbar.add("item", "calendar." .. name, options)
end

local heading = row("heading", "", {
	label = { font = { style = settings.font.style_map.Bold }, align = "center", width = width - 20 },
})
local previous =
	row("previous", "‹  Previous month", { label = { string = "‹  Previous month", color = colors.grey } })
row("weekdays", "", {
	icon = { string = "Wk", color = colors.grey, width = 24, font = { family = settings.font.icon, size = 12 } },
	label = {
		string = " Mo  Tu  We  Th  Fr  Sa  Su ",
		font = { family = settings.font.icon, size = 13 },
		width = width - 54,
		align = "left",
		padding_left = 18,
		color = colors.grey,
	},
})
local weeks = {}
for index = 1, 6 do
	weeks[index] = row("week." .. index, "", {
		icon = { width = 24, color = colors.grey, font = { family = settings.font.icon, size = 12 } },
		label = {
			font = { family = settings.font.icon, size = 13 },
			width = width - 54,
			align = "left",
			padding_left = 18,
		},
	})
end
local next_month = row("next", "Next month  ›", { label = { string = "Next month  ›", color = colors.grey } })
local today_row = row("today", "Today", { label = { string = "Today", color = colors.accent } })
local open_calendar =
	row("open", "Open Calendar  ↗", { label = { string = "Open Calendar  ↗", color = colors.blue } })

local viewed = os.date("*t")
local function render()
	local month = calendar.month(viewed.year, viewed.month)
	viewed.year, viewed.month = month.year, month.month
	heading:set({ label = month.title })
	for index, week in ipairs(month.weeks) do
		local cells, contains_today, contains_days = {}, false, false
		for _, day in ipairs(week.days) do
			local current = day.in_month and day.today
			cells[#cells + 1] = day.in_month and string.format(current and "[%02d]" or " %02d ", day.day) or "    "
			contains_today = contains_today or current
			contains_days = contains_days or day.in_month
		end
		weeks[index]:set({
			drawing = contains_days,
			icon = week.number,
			label = { string = table.concat(cells), color = contains_today and colors.accent or colors.white },
		})
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
	if cal:query().popup.drawing == "on" then
		render()
	end
end)

local details = popup.bind(cal, { settings_command = "open -a 'Calendar'", on_open = reset })
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
