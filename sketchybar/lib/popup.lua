local sbar = require("sketchybar")
local colors = require("colors")

local M = {}
local active
local panels = {}

function M.toggle(name)
	if panels[name] then
		panels[name]:toggle()
		return true
	end
	return false
end

function M.close_all()
	if active then
		active:close()
	end
end

function M.is_open(owner)
	if panels[owner.name] then
		return active == panels[owner.name]
	end
	local state = owner:query()
	return type(state) == "table" and type(state.popup) == "table" and state.popup.drawing == "on"
end

function M.bind(owner, options)
	options = options or {}
	local popup = {}

	function popup:close()
		if active ~= self then
			return
		end
		active = nil
		owner:set({ popup = { drawing = false }, background = { color = colors.transparent } })
		if options.on_close then
			options.on_close()
		end
	end

	function popup:toggle()
		if active == self then
			self:close()
			return
		end
		if active then
			active:close()
		end
		active = self
		owner:set({ popup = { drawing = true }, background = { color = colors.panel.selected } })
		if options.on_open then
			options.on_open()
		end
	end

	owner:subscribe("mouse.clicked", function(env)
		if env.BUTTON == "right" and options.settings_command then
			popup:close()
			sbar.exec(options.settings_command)
		else
			popup:toggle()
		end
	end)
	owner:subscribe("mouse.exited.global", function()
		popup:close()
	end)

	panels[owner.name] = popup
	return popup
end

return M
