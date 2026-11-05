local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")
local popup = require("lib.popup")
local panel = require("lib.panel")
local utils = require("lib.utils")

local root = os.getenv("CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar")
local command = utils.quote(root .. "/runtime/display-control")
local width, gap = settings.popup.width + 40, settings.popup.gap
local display = sbar.add("item", "widgets.display", {
	position = "right",
	icon = { string = "", color = colors.white },
	label = { drawing = false },
	background = { color = colors.transparent },
	popup = { align = "right", height = 1, columns = 4 },
})
local actions = {}
local function row(name, label, span, color)
	span = span or 4
	return sbar.add("item", "widgets.display." .. name, {
		position = "popup." .. display.name,
		cell_span = span,
		width = (width - 3 * gap) / 4 * span + (span - 1) * gap,
		align = "center",
		icon = { drawing = false },
		label = {
			string = label,
			color = color or colors.white,
			max_chars = 40,
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 12 },
		},
		background = { height = settings.popup.height, padding_left = 0, padding_right = 0 },
	})
end
local function action(item, enabled)
	local state = panel.action(item, { enabled = enabled ~= false })
	actions[#actions + 1] = state
	return state
end

local heading = row("heading", "Displays")
panel.heading(heading)
local picker, picker_actions = {}, {}
for index = 1, 6 do
	picker[index] = row("device." .. index, "")
	picker[index]:set({ drawing = false })
	picker_actions[index] = action(picker[index], false)
end
local mode = row("mode", "", 4, colors.grey)
mode:set({ label = { font = { size = 10 } } })
local brightness = row("brightness", "BRIGHTNESS")
panel.section(brightness)
local slider = sbar.add("slider", "widgets.display.slider", width - 54, {
	position = "popup." .. display.name,
	width = width,
	cell_span = 4,
	align = "center",
	icon = { drawing = true, string = "", width = 27, padding_left = 0, padding_right = 0 },
	label = { drawing = true, string = "", width = 27, padding_left = 0, padding_right = 0 },
	background = { padding_left = 0, padding_right = 0 },
	slider = {
		percentage = 0,
		highlight_color = colors.accent,
		background = { height = 5, corner_radius = 3, color = colors.bg2 },
		knob = {
			string = "",
			color = colors.white,
			font = { family = settings.font.icon, style = settings.font.style_map.Regular, size = 11 },
		},
	},
})
local slider_action = action(slider, false)
local presets, preset_actions = {}, {}
for index, percent in ipairs({ 25, 50, 75, 100 }) do
	presets[index] = row("preset." .. percent, percent .. "%", 1)
	preset_actions[index] = action(presets[index], false)
end
local message = row("message", "", 4, colors.grey)
message:set({ drawing = false, label = { font = { size = 10 } } })
local refresh = row("refresh", "Refresh", 2, colors.grey)
local refresh_action = action(refresh)
local betterdisplay = row("betterdisplay", "BetterDisplay ↗", 2, colors.blue)
action(betterdisplay)
local timer = sbar.add("item", "widgets.display.timer", { drawing = false, updates = true, update_freq = 0 })

local opened, reading, busy = false, false, false
local revision = 0
local displays, selected_uuid = {}, nil
local details

local function selected()
	for _, device in ipairs(displays) do
		if device.uuid == selected_uuid then
			return device
		end
	end
end

local function render()
	local device = selected()
	for index, item in ipairs(picker) do
		local entry = displays[index]
		local active = entry ~= nil and entry.uuid == selected_uuid
		item:set({
			drawing = entry ~= nil,
			label = {
				string = entry and ((active and "● " or "○ ") .. entry.name) or "",
				color = active and colors.accent or colors.white,
			},
		})
		picker_actions[index]:enable(entry ~= nil and not busy)
		picker_actions[index]:select(active)
	end
	local level = device and device.brightness
	local enabled = level ~= nil and not busy
	brightness:set({ label = level and string.format("BRIGHTNESS · %.0f%%", level) or "BRIGHTNESS UNAVAILABLE" })
	slider:set({ drawing = enabled or busy and level ~= nil, slider = { percentage = level or 0 } })
	slider_action:enable(enabled)
	for index, percent in ipairs({ 25, 50, 75, 100 }) do
		preset_actions[index]:enable(enabled)
		preset_actions[index]:select(level ~= nil and math.abs(level - percent) < 0.5)
	end
	local resolution = device and device.resolution
	local rate = device and device.refresh_rate
	mode:set({
		label = resolution and (resolution .. (rate and " · " .. rate or "")) or "Mode information unavailable",
	})
	refresh_action:enable(not busy and not reading)
end

local function notify(text, failed)
	message:set({
		drawing = text ~= nil,
		label = { string = text or "", color = failed and colors.red or colors.accent },
	})
end

local function valid_device(device)
	return type(device) == "table"
		and type(device.uuid) == "string"
		and device.uuid:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
		and type(device.name) == "string"
		and (
			device.brightness == nil
			or type(device.brightness) == "number"
				and device.brightness == device.brightness
				and device.brightness >= 0
				and device.brightness <= 100
		)
end

local function refresh_displays(full)
	if not opened or reading or busy then
		return
	end
	reading = true
	revision = revision + 1
	local request = revision
	refresh_action:enable(false)
	if full then
		notify(nil)
	end
	sbar.exec(command .. (full and " snapshot" or " levels"), function(result, code)
		if request ~= revision or not opened then
			return
		end
		reading = false
		local previous = {}
		for _, device in ipairs(displays) do
			previous[device.uuid] = device
		end
		displays = {}
		if code == 0 and type(result) == "table" and result.ok == true and type(result.displays) == "table" then
			for _, device in ipairs(result.displays) do
				if valid_device(device) then
					local known = previous[device.uuid]
					if not full and known then
						device.resolution, device.refresh_rate = known.resolution, known.refresh_rate
					end
					displays[#displays + 1] = device
				end
			end
			if not selected() then
				selected_uuid = result.mouse_uuid
				if not selected() then
					selected_uuid = displays[1] and displays[1].uuid
				end
			end
			if #displays == 0 then
				notify("No connected displays · Open BetterDisplay", true)
			elseif full then
				notify(nil)
			end
		else
			notify("BetterDisplay unavailable · Open BetterDisplay", true)
		end
		render()
	end)
end

local function set_brightness(value)
	local device = selected()
	local percent = tonumber(value)
	if
		busy
		or not opened
		or not device
		or device.brightness == nil
		or not percent
		or percent ~= percent
		or percent < 0
		or percent > 100
	then
		return
	end
	percent = math.floor(percent + 0.5)
	local uuid = device.uuid
	busy, reading = true, false
	revision = revision + 1
	notify("Adjusting brightness…")
	render()
	sbar.exec(command .. " brightness " .. utils.quote(uuid) .. " " .. percent, function(result, code)
		busy = false
		local actual = type(result) == "table" and result.brightness
		local verified = type(actual) == "number" and actual == actual and actual >= 0 and actual <= 100
		if verified and result.uuid == uuid then
			device.brightness = actual
		end
		if not opened then
			return
		end
		if code == 0 and type(result) == "table" and result.ok == true and result.uuid == uuid and verified then
			notify(nil)
		else
			notify("Brightness change failed · Refresh or use BetterDisplay", true)
		end
		render()
		if not selected() then
			refresh_displays(true)
		end
	end)
end

for index, item in ipairs(picker) do
	item:subscribe("mouse.clicked", function()
		if busy or not opened or not displays[index] then
			return
		end
		selected_uuid = displays[index].uuid
		notify(nil)
		render()
	end)
end
slider:subscribe("mouse.clicked", function(env)
	set_brightness(env.PERCENTAGE)
end)
for index, percent in ipairs({ 25, 50, 75, 100 }) do
	presets[index]:subscribe("mouse.clicked", function()
		set_brightness(percent)
	end)
end
refresh:subscribe("mouse.clicked", function()
	refresh_displays(true)
end)
timer:subscribe("routine", function()
	refresh_displays(false)
end)
display:subscribe({ "display_change", "system_woke" }, function()
	refresh_displays(true)
end)

details = popup.bind(display, {
	settings_command = settings.commands.display,
	on_open = function()
		opened = true
		if #displays == 0 then
			notify("Checking displays…")
		end
		render()
		timer:set({ update_freq = 10 })
		refresh_displays(true)
	end,
	on_close = function()
		opened, reading = false, false
		revision = revision + 1
		timer:set({ update_freq = 0 })
		for _, state in ipairs(actions) do
			state:reset()
		end
	end,
})
betterdisplay:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec("/opt/homebrew/bin/betterdisplaycli set --appMenu=on", function(_, code)
		if code ~= 0 then
			sbar.exec("/usr/bin/open -a BetterDisplay")
		end
	end)
end)
return display
