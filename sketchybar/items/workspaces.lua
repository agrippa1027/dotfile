local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")
local utils = require("lib.utils")

local workspace_order = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a" }
local workspaces = {}
local space_indices = {}

sbar.add("event", "yabai_workspace_change")

for _, id in ipairs(workspace_order) do
	local workspace = id
	local item = sbar.add("item", "workspace." .. workspace, {
		position = "left",

		drawing = false,
		width = settings.workspaces.width,
		icon = {
			string = workspace,
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 12 },
			width = settings.workspaces.width,
			align = "center",
			padding_left = 0,
			padding_right = 0,
		},
		label = { drawing = false },
		background = { drawing = false, color = colors.transparent, corner_radius = 0, border_width = 0 },
		padding_left = 0,
		padding_right = settings.workspaces.gap,
	})
	item:subscribe("mouse.clicked", function()
		local index = space_indices[workspace]
		if index then
			sbar.exec("/opt/homebrew/bin/yabai -m space --focus " .. utils.quote(index))
		end
	end)
	workspaces[workspace] = item
end

local started_at
local generation = 0
local pending = false
local function refresh()
	local now = os.time()
	-- Coalesce bursts; allow recovery after SbarLua's 60-second exec deadline.
	if started_at and now - started_at < 65 then
		pending = true
		return
	end
	generation = generation + 1
	local request = generation
	started_at = now
	pending = false

	local function finish()
		started_at = nil
		if pending then
			refresh()
		end
	end

	sbar.exec("/opt/homebrew/bin/yabai -m query --spaces", function(assignments, status)
		if request ~= generation then
			return
		end
		if pending or status ~= 0 or type(assignments) ~= "table" or #assignments == 0 then
			finish()
			return
		end

		local active = {}
		local layouts = {}
		local displays = {}
		local indices = {}
		local names = {}
		for key, assignment in pairs(assignments) do
			if
				type(key) ~= "number"
				or type(assignment) ~= "table"
				or type(assignment.index) ~= "number"
				or type(assignment.display) ~= "number"
			then
				finish()
				return
			end
			if not assignment["is-native-fullscreen"] then
				local workspace = assignment.label
				if type(workspace) ~= "string" or workspace == "" then
					workspace = tostring(assignment.index)
				else
					workspace = workspace:gsub("^ws%-", "")
				end
				if workspaces[workspace] then
					-- Both tools use native display ordering (yabai: display_arrangement_order=default).
					displays[workspace] = assignment.display
					indices[workspace] = assignment.index
					names[assignment.index] = workspace
					active[workspace] = assignment["has-focus"] or assignment["is-visible"]
					layouts[workspace] = assignment.type
				end
			end
		end

		started_at = os.time()
		sbar.exec("/opt/homebrew/bin/yabai -m query --windows", function(windows, result)
			if request ~= generation then
				return
			end
			if pending or result ~= 0 or type(windows) ~= "table" then
				finish()
				return
			end
			local occupied = {}
			for key, window in pairs(windows) do
				if
					type(key) ~= "number"
					or type(window) ~= "table"
					or type(window.space) ~= "number"
					or type(window.app) ~= "string"
				then
					finish()
					return
				end
				local workspace = names[window.space]
				local app = window.app
				if workspace and app ~= "" then
					occupied[workspace] = true
				end
			end

			space_indices = indices
			for _, workspace in ipairs(workspace_order) do
				local marker = layouts[workspace] == "float" and "▲" or "■"
				workspaces[workspace]:set({
					drawing = displays[workspace] ~= nil,
					display = displays[workspace] or 0,
					icon = {
						string = active[workspace] and marker or workspace,
						color = (active[workspace] or occupied[workspace]) and colors.white
							or colors.bar.workspace_empty,
					},
				})
			end
			finish()
		end)
	end)
end

local state = sbar.add("item", "workspace_state", { drawing = false, updates = true })
-- yabai supplies focus/space/display events; native window events also cover app hide/show.
state:subscribe({ "forced", "yabai_workspace_change", "space_windows_change" }, refresh)
refresh()
