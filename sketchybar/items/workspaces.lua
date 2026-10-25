local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")
local utils = require("lib.utils")
local app_icons = require("vendor.app-font.icon_map")
local workspace_order = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a" }
local workspaces = {}
local space_indices = {}

sbar.add("event", "yabai_workspace_change")

for _, id in ipairs(workspace_order) do
	local workspace = id
	local item = sbar.add("item", "workspace." .. workspace, {
		position = "left",

		drawing = false,
		icon = {
			string = workspace,
			font = { family = "Comic Code Ligatures", style = "Regular", size = 13 },
			padding_left = 6,
			padding_right = 5,
		},
		label = {
			font = { family = "sketchybar-app-font", style = "Regular", size = 15 },
			padding_left = 3,
			padding_right = 6,
		},
		background = { color = colors.transparent, corner_radius = 7 },
		padding_left = 2,
		padding_right = 2,
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

		local focused
		local displays = {}
		local display_counts = {}
		local display_edges = {}
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
					display_counts[assignment.display] = (display_counts[assignment.display] or 0) + 1
					indices[workspace] = assignment.index
					names[assignment.index] = workspace
					if assignment["has-focus"] then
						focused = workspace
					end
				end
			end
		end

		for _, workspace in ipairs(workspace_order) do
			local display = displays[workspace]
			if display then
				display_edges[display] = display_edges[display] or { first = workspace }
				display_edges[display].last = workspace
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
			local apps = {}
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
					apps[workspace] = apps[workspace] or {}
					apps[workspace][app] = true
				end
			end

			space_indices = indices
			for _, workspace in ipairs(workspace_order) do
				local labels = {}
				for app in pairs(apps[workspace] or {}) do
					labels[#labels + 1] = app_icons[app] or ":default:"
				end
				table.sort(labels)
				local active = workspace == focused
				local display = displays[workspace]
				local edges = display_edges[display] or {}
				local edge_padding = (display_counts[display] or 0) < 4 and settings.workspaces.small_group_edge_padding
					or 2
				workspaces[workspace]:set({
					drawing = displays[workspace] ~= nil,
					display = displays[workspace] or 0,
					width = "dynamic",
					padding_left = edges.first == workspace and edge_padding or 2,
					padding_right = edges.last == workspace and edge_padding or 2,
					icon = {
						color = active and colors.black or (#labels > 0 and colors.white or colors.grey),
						padding_left = #labels > 0 and 6 or 13,
						padding_right = #labels > 0 and 5 or 12,
					},
					label = {
						string = table.concat(labels, " "),
						drawing = #labels > 0,
						color = active and colors.black or colors.white,
					},
					background = { color = active and colors.accent or colors.transparent },
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
