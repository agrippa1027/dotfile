local sbar = require("sketchybar")
local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local popup = require("lib.popup")
local panel = require("lib.panel")

local battery = sbar.add("item", "widgets.battery", {
	position = "right",
	icon = {
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	update_freq = 180,
	background = { color = colors.transparent },
	popup = { align = "right", height = settings.popup.height },
})

local width = settings.popup.width
local heading = sbar.add("item", "widgets.battery.heading", {
	position = "popup." .. battery.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	align = "center",
	icon = { drawing = false },
	label = { string = "Power", color = colors.white },
})
panel.heading(heading)

local function readout(name, caption, value)
	return sbar.add("item", "widgets.battery." .. name, {
		position = "popup." .. battery.name,
		width = width,
		background = { padding_left = 0, padding_right = 0 },
		icon = {
			string = caption,
			color = colors.grey,
			width = 116,
			align = "left",
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 10 },
		},
		label = {
			string = value,
			color = colors.white,
			width = width - 136,
			align = "right",
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 12 },
		},
	})
end
local source = readout("source", "SOURCE", "Checking…")
local status_item = readout("status", "STATUS", "Checking…")
local remaining_time = readout("remaining", "ESTIMATE", "No estimate")
local open_settings = sbar.add("item", "widgets.battery.settings", {
	position = "popup." .. battery.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	align = "center",
	icon = { drawing = false },
	label = { string = "Battery Settings  ↗", color = colors.blue, font = { family = settings.font.text, size = 12 } },
})
local settings_action = panel.action(open_settings)

local function parse(result, status)
	if status ~= 0 or type(result) ~= "string" then
		return
	end
	local power_source = result:match("Now drawing from '([^']+)'")
	local charge, state = result:match("%s(%d+)%%;%s*([^;\r\n]+)")
	charge = tonumber(charge)
	if (power_source ~= "AC Power" and power_source ~= "Battery Power") or not charge or charge > 100 then
		return
	end
	state = state:match("^%s*(.-)%s*$")
	local info = {
		source = power_source,
		charge = charge,
		status = "Unavailable",
		caption = "ESTIMATE",
		estimate = "No estimate",
	}
	if power_source == "Battery Power" then
		info.status, info.caption = "On battery", "TIME REMAINING"
	elseif state == "charging" or state == "finishing charge" then
		info.status, info.caption = "Charging", "TIME TO FULL"
	elseif state == "charged" then
		info.status, info.estimate = "Fully charged", "Not needed"
	elseif state == "discharging" then
		info.status, info.caption = "Discharging", "TIME REMAINING"
	elseif state == "AC attached" or state:match("^not charging") then
		info.status = "Not charging"
	end
	if info.caption ~= "ESTIMATE" then
		local hours, minutes = result:match("%s(%d+):(%d%d)%s+remaining")
		if hours and tonumber(minutes) < 60 then
			info.estimate = hours .. ":" .. minutes .. "h"
		end
	end
	return info
end

local function render(info)
	local icon, label, color = "!", "?", colors.grey
	if info then
		local charge = info.charge
		label, color = string.format("%02d%%", charge), colors.white
		-- Keep the existing AC glyph, even when the battery is full or charging is paused.
		if info.source == "AC Power" then
			icon = icons.battery.charging
		elseif charge > 80 then
			icon = icons.battery._100
		elseif charge > 60 then
			icon = icons.battery._75
		elseif charge > 40 then
			icon = icons.battery._50
		elseif charge > 20 then
			icon, color = icons.battery._25, colors.orange
		else
			icon, color = icons.battery._0, colors.red
		end
	end
	battery:set({ icon = { string = icon, color = color }, label = label })
	source:set({ label = info and info.source or "Unavailable" })
	status_item:set({ label = info and info.status or "Unavailable" })
	remaining_time:set({
		icon = info and info.caption or "ESTIMATE",
		label = info and info.estimate or "No estimate",
	})
end

local revision = 0
local function refresh()
	revision = revision + 1
	local request = revision
	sbar.exec("pmset -g batt", function(result, status)
		if request == revision then
			render(parse(result, status))
		end
	end)
end
battery:subscribe({ "forced", "routine", "power_source_change", "system_woke" }, refresh)

local details = popup.bind(battery, {
	settings_command = settings.commands.battery,
	on_open = function()
		settings_action:reset()
		refresh()
	end,
	on_close = function()
		settings_action:reset()
	end,
})
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.battery)
end)

return battery
