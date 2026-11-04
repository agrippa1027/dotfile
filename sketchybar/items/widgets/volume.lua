local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("lib.popup")
local panel = require("lib.panel")
local utils = require("lib.utils")

local width = settings.popup.width
local audio_source = "/opt/homebrew/bin/SwitchAudioSource"

local volume = sbar.add("item", "widgets.volume", {
	position = "right",
	icon = {
		string = icons.volume._100,
		color = colors.grey,
		font = { family = settings.font.icon, style = settings.font.style_map.Regular, size = 14 },
	},
	label = { string = "??%", font = { family = settings.font.text, size = 12 } },
	background = { color = colors.transparent },
	popup = {
		align = "right",
		height = settings.popup.height,
		blur_radius = 0,
		background = {
			color = colors.popup.bg,
			border_color = colors.accent,
			border_width = settings.popup.border_width,
			corner_radius = settings.popup.corner_radius,
		},
	},
})

local heading = sbar.add("item", "widgets.volume.heading", {
	position = "popup." .. volume.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = { drawing = false },
	label = { string = "Master volume", color = colors.white },
	align = "center",
})
panel.heading(heading)
local slider = sbar.add("slider", "widgets.volume.slider", width - 80, {
	position = "popup." .. volume.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = { string = icons.volume._100, width = 30, color = colors.grey },
	label = { drawing = false },
	slider = {
		percentage = 0,
		highlight_color = colors.accent,
		background = { height = 5, corner_radius = 3, color = colors.bg2 },
		knob = { string = "●", color = colors.white, font = { size = 11 } },
	},
})
local outputs_heading = sbar.add("item", "widgets.volume.outputs", {
	position = "popup." .. volume.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = { drawing = false },
	label = { string = "OUTPUT DEVICES" },
})
panel.section(outputs_heading)
local output_items = {}
local output_names = {}
local output_actions = {}
local slider_action = panel.action(slider)
for index = 1, 6 do
	output_items[index] = sbar.add("item", "widgets.volume.output." .. index, {
		position = "popup." .. volume.name,
		width = width,
		background = { padding_left = 0, padding_right = 0 },
		drawing = false,
		icon = { string = "○", width = 24, color = colors.grey },
		label = {
			max_chars = 29,
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 12 },
		},
	})
	output_actions[index] = panel.action(output_items[index], { enabled = false })
end
local open_settings = sbar.add("item", "widgets.volume.settings", {
	position = "popup." .. volume.name,
	width = width,
	background = { padding_left = 0, padding_right = 0 },
	icon = { drawing = false },
	align = "center",
	label = { string = "Sound settings  ↗", color = colors.blue, font = { family = settings.font.text, size = 12 } },
})

local settings_action = panel.action(open_settings)
local function reset_hover()
	slider_action:reset()
	settings_action:reset()
	for _, state in ipairs(output_actions) do
		state:reset()
	end
end

local revision = 0

local function update(env)
	local level = tonumber(env.INFO)
	if not level or level ~= level or level < 0 or level > 100 then
		return
	end
	level = math.floor(level + 0.5)
	revision = revision + 1

	local icon = icons.volume._0
	if level > 60 then
		icon = icons.volume._100
	elseif level > 30 then
		icon = icons.volume._66
	elseif level > 10 then
		icon = icons.volume._33
	elseif level > 0 then
		icon = icons.volume._10
	end

	volume:set({ icon = icon, label = string.format("%02d%%", level) })
	slider:set({ slider = { percentage = level } })
	heading:set({ label = "Master volume · " .. level .. "%" })
end

volume:subscribe("volume_change", update)
local function read_volume()
	revision = revision + 1
	local current = revision
	sbar.exec("osascript -e 'output volume of (get volume settings)'", function(result, status)
		if status == 0 and current == revision then
			update({ INFO = result })
		end
	end)
end
volume:subscribe({ "forced", "system_woke" }, read_volume)

local output_revision = 0
local function read_outputs()
	output_revision = output_revision + 1
	local request = output_revision
	output_names = {}
	outputs_heading:set({ label = "CHECKING OUTPUTS…" })
	for index, item in ipairs(output_items) do
		item:set({ drawing = false })
		output_actions[index]:select(false)
		output_actions[index]:enable(false)
		output_actions[index]:reset()
	end
	sbar.exec(audio_source .. " -a -t output 2>/dev/null", function(result, status)
		if request ~= output_revision or volume:query().popup.drawing ~= "on" then
			return
		end
		local names, seen = {}, {}
		if status == 0 and type(result) == "string" then
			for line in result:gmatch("[^\r\n]+") do
				local name = utils.trim(line)
				if name ~= "" and not seen[name] then
					names[#names + 1] = name
					seen[name] = true
				end
			end
		end
		if #names == 0 then
			outputs_heading:set({ label = "OUTPUTS UNAVAILABLE · USE SETTINGS" })
			return
		end
		sbar.exec(audio_source .. " -c -t output 2>/dev/null", function(current, current_status)
			if request ~= output_revision or volume:query().popup.drawing ~= "on" then
				return
			end
			current = current_status == 0 and type(current) == "string" and utils.trim(current) or nil
			table.sort(names, function(a, b)
				if a == b then
					return false
				end
				if a == current or b == current then
					return a == current
				end
				return a < b
			end)
			outputs_heading:set({
				label = #names > #output_items and "OUTPUT DEVICES · MORE IN SETTINGS" or "OUTPUT DEVICES",
			})
			for index, item in ipairs(output_items) do
				local name = names[index]
				output_names[index] = name
				output_actions[index]:enable(name ~= nil)
				output_actions[index]:select(name ~= nil and name == current)
				item:set({
					drawing = name ~= nil,
					icon = {
						string = name == current and "●" or "○",
						color = name == current and colors.accent or colors.grey,
					},
					label = { string = name or "", color = name == current and colors.white or colors.grey },
				})
			end
		end)
	end)
end

slider:subscribe("mouse.clicked", function(env)
	local percentage = tonumber(env.PERCENTAGE)
	if not percentage or percentage ~= percentage or percentage < 0 or percentage > 100 then
		return
	end
	percentage = math.floor(percentage + 0.5)
	revision = revision + 1
	sbar.exec("osascript -e 'set volume output volume " .. percentage .. "'", read_volume)
end)

for index, item in ipairs(output_items) do
	item:subscribe("mouse.clicked", function()
		local name = output_names[index]
		if not name then
			return
		end
		output_revision = output_revision + 1
		local request = output_revision
		sbar.exec(audio_source .. " -t output -s " .. utils.quote(name) .. " 2>/dev/null", function(_, status)
			if request ~= output_revision then
				return
			end
			read_volume()
			if volume:query().popup.drawing == "on" then
				if status == 0 then
					read_outputs()
				else
					outputs_heading:set({ label = "SWITCH FAILED · USE SETTINGS" })
				end
			end
		end)
	end)
end

volume:subscribe("mouse.scrolled", function(env)
	if type(env.INFO) ~= "table" then
		return
	end
	local delta = tonumber(env.INFO.delta)
	if not delta then
		return
	end
	if env.INFO.modifier ~= "ctrl" then
		delta = delta * 10.0
	end
	if delta == 0 or delta ~= delta or math.abs(delta) == math.huge then
		return
	end
	sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. delta .. ')"')
end)

local details = popup.bind(volume, {
	settings_command = settings.commands.sound,
	on_open = function()
		reset_hover()
		read_volume()
		read_outputs()
	end,
	on_close = reset_hover,
})
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.sound)
end)

return volume
