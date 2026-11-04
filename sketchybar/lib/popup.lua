local sbar = require("sketchybar")

local M = {}
local active

function M.is_open(owner)
	local state = owner:query()
	return type(state) == "table" and type(state.popup) == "table" and state.popup.drawing == "on"
end

function M.bind(owner, options)
	options = options or {}
	local popup = {}

	function popup:close()
		local was_open = active == self or M.is_open(owner)
		owner:set({ popup = { drawing = false } })
		if was_open and options.on_close then
			options.on_close()
		end
		if active == self then
			active = nil
		end
	end

	function popup:toggle()
		if M.is_open(owner) then
			self:close()
			return
		end
		if active then
			active:close()
		end
		active = self
		owner:set({ popup = { drawing = true } })
		if options.on_open then
			options.on_open()
		end
	end

	owner:subscribe("mouse.clicked", function(env)
		if env.BUTTON == "right" and options.settings_command then
			sbar.exec(options.settings_command)
		else
			popup:toggle()
		end
	end)
	owner:subscribe("mouse.exited.global", function()
		popup:close()
	end)

	return popup
end

return M
