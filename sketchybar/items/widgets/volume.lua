local sbar = require("sketchybar")
local colors = require("colors")
-- Adapted from FelixKratz/dotfiles; see vendor/README.md (GPL-3.0).
local utils = require("lib.utils")
local icons = require("icons")
local settings = require("settings")
local popup = require("lib.popup")

local popup_width = settings.popup.volume_width

local volume_percent = sbar.add("item", "widgets.volume1", {
	position = "right",
	icon = { drawing = false },
	label = {
		string = "??%",
		padding_left = -1,
	},
})

local volume_icon = sbar.add("item", "widgets.volume2", {
	position = "right",
	padding_right = -1,
	icon = {
		string = icons.volume._100,
		width = 0,
		align = "left",
		color = colors.grey,
		font = {
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
	label = {
		width = 25,
		align = "left",
		font = {
			family = settings.font.icon,
			style = settings.font.style_map["Regular"],
			size = 14.0,
		},
	},
})

local volume_bracket = sbar.add("bracket", "widgets.volume.bracket", {
	volume_icon.name,
	volume_percent.name,
}, {
	background = { color = colors.bg1 },
	popup = { align = "center" },
})

sbar.add("item", "widgets.volume.padding", {
	position = "right",
	width = settings.group_paddings,
})

local volume_slider = sbar.add("slider", popup_width, {
	position = "popup." .. volume_bracket.name,
	slider = {
		highlight_color = colors.blue,
		background = {
			height = 6,
			corner_radius = 3,
			color = colors.bg2,
		},
		knob = {
			string = "●",
			font = { family = settings.font.text, size = 10 },
			drawing = true,
		},
	},
	background = { color = colors.bg1, height = 2, y_offset = -20 },
	click_script = 'osascript -e "set volume output volume $PERCENTAGE"',
})

local function update_volume(env)
	local volume = tonumber(env.INFO)
	if not volume then
		return
	end
	local icon = icons.volume._0
	if volume > 60 then
		icon = icons.volume._100
	elseif volume > 30 then
		icon = icons.volume._66
	elseif volume > 10 then
		icon = icons.volume._33
	elseif volume > 0 then
		icon = icons.volume._10
	end

	local lead = ""
	if volume < 10 then
		lead = "0"
	end

	volume_icon:set({ label = icon })
	volume_percent:set({ label = lead .. volume .. "%" })
	volume_slider:set({ slider = { percentage = volume } })
end
volume_percent:subscribe("volume_change", update_volume)
volume_percent:subscribe("forced", function()
	sbar.exec("osascript -e 'output volume of (get volume settings)'", function(result)
		update_volume({ INFO = utils.trim(result) })
	end)
end)

local details
details = popup.bind(volume_bracket, {
	triggers = { volume_icon, volume_percent },
	settings_command = settings.commands.sound,
	on_close = function()
		sbar.remove("/volume[.]device[.].*/")
	end,
	on_open = function(is_current)
		sbar.exec("SwitchAudioSource -t output -c", function(result)
			if not is_current() then
				return
			end
			local current_audio_device = utils.trim(result)
			sbar.exec("SwitchAudioSource -a -t output", function(available)
				if not is_current() then
					return
				end
				sbar.remove("/volume[.]device[.].*/")
				local counter = 0

				for device in string.gmatch(available, "[^\r\n]+") do
					local color = colors.grey
					if current_audio_device == device then
						color = colors.white
					end
					local device_item = sbar.add("item", "volume.device." .. counter, {
						position = "popup." .. volume_bracket.name,
						width = popup_width,
						align = "center",
						label = { string = device, color = color },
						click_script = "SwitchAudioSource -s "
							.. utils.quote(device)
							.. " && sketchybar --set /volume[.]device[.].*/ label.color="
							.. colors.grey
							.. ' --set "$NAME" label.color='
							.. colors.white,
					})
					details:watch(device_item)
					counter = counter + 1
				end
			end)
		end)
	end,
})
details:watch(volume_slider)

local function volume_scroll(env)
	local delta = env.INFO.delta
	if not (env.INFO.modifier == "ctrl") then
		delta = delta * 10.0
	end

	sbar.exec('osascript -e "set volume output volume (output volume of (get volume settings) + ' .. delta .. ')"')
end

volume_icon:subscribe("mouse.scrolled", volume_scroll)
volume_percent:subscribe("mouse.scrolled", volume_scroll)
