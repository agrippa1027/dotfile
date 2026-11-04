local colors = require("colors")
local settings = require("settings")

local M = {}

-- Keep transient hover separate from selection so leaving a control restores it.
function M.action(item, options)
	options = options or {}
	local hovered, selected, enabled = false, options.selected or false, options.enabled ~= false
	local state = {}
	local function render()
		item:set({
			background = {
				drawing = true,
				height = settings.popup.control_height,
				padding_left = 0,
				padding_right = 0,
				corner_radius = settings.popup.corner_radius,
				color = enabled
						and (hovered and colors.panel.hover or selected and colors.panel.selected or colors.panel.control)
					or colors.transparent,
				border_width = enabled and 1 or 0,
				border_color = hovered and colors.panel.hover_border or colors.panel.control_border,
			},
		})
	end
	function state:select(value)
		selected = value
		render()
	end
	function state:enable(value)
		enabled = value
		render()
	end
	function state:reset()
		hovered = false
		render()
	end
	item:subscribe("mouse.entered", function()
		hovered = true
		render()
	end)
	item:subscribe("mouse.exited", function()
		hovered = false
		render()
	end)
	render()
	return state
end

function M.heading(item)
	item:set({
		background = { height = 42, padding_left = 0, padding_right = 0 },
		label = { font = { family = settings.font.text, style = settings.font.style_map.Bold, size = 14 } },
	})
end

function M.section(item)
	item:set({
		background = { height = 28, padding_left = 0, padding_right = 0 },
		label = { color = colors.grey, font = { family = settings.font.text, size = 10 } },
	})
end

return M
