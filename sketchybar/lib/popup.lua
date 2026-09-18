local sbar = require("sketchybar")
local settings = require("settings")

local M = {}
local active
local pointer_command =
	[[osascript -l JavaScript -e 'ObjC.import("CoreGraphics"); var event = $.CGEventCreate(null); var point = $.CGEventGetLocation(event); point.x + " " + point.y']]
local events = sbar.add("item", "popup.events", { drawing = false, updates = true })
events:subscribe("mouse.exited.global", function()
	if active then
		active:close()
	end
end)

function M.bind(owner, options)
	options = options or {}
	local popup = { generation = 0 }
	local revision = 0

	function popup:is_open()
		return owner:query().popup.drawing == "on"
	end

	function popup:close()
		local was_open = self:is_open()
		self.generation = self.generation + 1
		revision = revision + 1
		owner:set({ popup = { drawing = false } })
		if active == self then
			active = nil
		end
		if was_open and options.on_close then
			options.on_close()
		end
	end

	function popup:toggle()
		if self:is_open() then
			self:close()
			return
		end
		if active and active ~= self then
			active:close()
		end
		active = self
		revision = revision + 1
		self.generation = self.generation + 1
		local generation = self.generation
		owner:set({ popup = { drawing = true } })
		if options.on_open then
			options.on_open(function()
				return self.generation == generation and self:is_open()
			end)
		end
	end

	local function inside(x, y)
		local function contains(rect)
			return x >= rect.origin[1]
				and x <= rect.origin[1] + rect.size[1]
				and y >= rect.origin[2]
				and y <= rect.origin[2] + rect.size[2]
		end
		for _, trigger in ipairs(options.triggers or { owner }) do
			for _, rect in pairs(trigger:query().bounding_rects) do
				if contains(rect) then
					return true
				end
			end
		end
		local frames = {}
		local properties = owner:query().popup
		local border = properties.background.border_width
		for _, name in ipairs(properties.items) do
			local child = sbar.query(name)
			local padding = child.geometry.background
			for display, rect in pairs(child.bounding_rects) do
				if rect.origin[1] ~= -10000 and rect.origin[2] ~= -10000 then
					local left = rect.origin[1] - padding.padding_left
					local top = rect.origin[2] - border
					local right = rect.origin[1] + rect.size[1] + padding.padding_right + border
					local bottom = rect.origin[2] + rect.size[2] + border
					local frame = frames[display] or { left, top, right, bottom }
					frames[display] = {
						math.min(frame[1], left),
						math.min(frame[2], top),
						math.max(frame[3], right),
						math.max(frame[4], bottom),
					}
				end
			end
		end
		for _, frame in pairs(frames) do
			if contains({ origin = { frame[1], frame[2] }, size = { frame[3] - frame[1], frame[4] - frame[2] } }) then
				return true
			end
		end
		return false
	end

	function popup:watch(item)
		item:subscribe("mouse.entered", function()
			revision = revision + 1
		end)
		item:subscribe("mouse.exited", function()
			revision = revision + 1
			local current = revision
			if popup:is_open() then
				-- Native global exit can be missed after re-entering a popup.
				sbar.delay(settings.popup.close_delay, function()
					if revision ~= current or not popup:is_open() then
						return
					end
					sbar.exec(pointer_command, function(result)
						if revision ~= current or not popup:is_open() then
							return
						end
						local x, y = result:match("([%-%.%d]+)%s+([%-%.%d]+)")
						x, y = tonumber(x), tonumber(y)
						if x and y and not inside(x, y) then
							popup:close()
						end
					end)
				end)
			end
		end)
	end

	-- Keep global exit on the shared receiver so native owner re-entry works.
	popup:watch(owner)
	for _, trigger in ipairs(options.triggers or { owner }) do
		if trigger ~= owner then
			popup:watch(trigger)
		end
		trigger:subscribe("mouse.clicked", function(env)
			if env.BUTTON == "right" and options.settings_command then
				sbar.exec(options.settings_command)
			else
				popup:toggle()
			end
		end)
	end
	return popup
end

return M
