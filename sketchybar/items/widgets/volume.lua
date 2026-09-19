local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local volume = sbar.add("item", "widgets.volume", {
	position = "right",
	icon = {
		string = icons.volume._100,
		color = colors.grey,
		font = { family = settings.font.icon, style = settings.font.style_map.Regular, size = 14 },
	},
	label = { string = "??%" },
	background = { color = colors.transparent },
})

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
end

volume:subscribe("volume_change", update)
volume:subscribe({ "forced", "system_woke" }, function()
	revision = revision + 1
	local current = revision
	sbar.exec("osascript -e 'output volume of (get volume settings)'", function(result, status)
		if status == 0 and current == revision then
			update({ INFO = result })
		end
	end)
end)

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

volume:subscribe("mouse.clicked", function(env)
	if env.BUTTON == "right" then
		sbar.exec(settings.commands.sound)
	end
end)
