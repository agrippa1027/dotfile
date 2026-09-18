local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

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

sbar.add("bracket", "widgets.volume.bracket", {
	volume_icon.name,
	volume_percent.name,
}, {
	background = { color = colors.bg1 },
})

sbar.add("item", "widgets.volume.padding", {
	position = "right",
	width = settings.group_paddings,
})

local volume_revision = 0

local function update_volume(env)
	local volume = tonumber(env.INFO)
	if not volume or volume ~= volume or volume < 0 or volume > 100 then
		return
	end
	volume = math.floor(volume + 0.5)
	volume_revision = volume_revision + 1
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

	volume_icon:set({ label = icon })
	volume_percent:set({ label = string.format("%02d%%", volume) })
end
volume_percent:subscribe("volume_change", update_volume)
volume_percent:subscribe({ "forced", "system_woke" }, function()
	volume_revision = volume_revision + 1
	local revision = volume_revision
	sbar.exec("osascript -e 'output volume of (get volume settings)'", function(result, exit_code)
		-- A volume event or a newer refresh takes precedence over this snapshot.
		if exit_code == 0 and revision == volume_revision then
			update_volume({ INFO = result })
		end
	end)
end)

local function volume_scroll(env)
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
end

volume_icon:subscribe("mouse.scrolled", volume_scroll)
volume_percent:subscribe("mouse.scrolled", volume_scroll)

local function volume_click(env)
	if env.BUTTON == "right" then
		sbar.exec(settings.commands.sound)
	end
end

volume_icon:subscribe("mouse.clicked", volume_click)
volume_percent:subscribe("mouse.clicked", volume_click)
