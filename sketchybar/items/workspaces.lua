local sbar = require("sketchybar")
local colors = require("colors")
local utils = require("lib.utils")
local app_icons = require("vendor.app-font.icon_map")
local workspaces = {}

sbar.add("event", "aerospace_workspace_change")

for _, id in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "a" }) do
	local workspace = id
	local item = sbar.add("item", "workspace." .. workspace, {
		position = "left",
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
		background = { color = colors.bg1, corner_radius = 7 },
		padding_left = 2,
		padding_right = 2,
	})
	item:subscribe("mouse.clicked", function()
		sbar.exec("/opt/homebrew/bin/aerospace workspace " .. utils.quote(workspace))
	end)
	workspaces[workspace] = item
end

local revision = 0
local function refresh()
	revision = revision + 1
	local current = revision
	sbar.exec("/opt/homebrew/bin/aerospace list-workspaces --focused", function(focused, status)
		if status ~= 0 or current ~= revision then
			return
		end

		focused = utils.trim(focused)
		sbar.exec(
			"/opt/homebrew/bin/aerospace list-windows --all --format '%{workspace}%{tab}%{app-name}' --json",
			function(windows, result)
				if result ~= 0 or type(windows) ~= "table" or current ~= revision then
					return
				end
				local apps = {}
				for _, window in ipairs(windows) do
					local workspace = window.workspace
					local app = window["app-name"]
					if workspace and app then
						apps[workspace] = apps[workspace] or {}
						apps[workspace][app] = true
					end
				end
				for workspace, item in pairs(workspaces) do
					local labels = {}
					for app in pairs(apps[workspace] or {}) do
						labels[#labels + 1] = app_icons[app] or ":default:"
					end
					table.sort(labels)
					local active = workspace == focused
					local visible = active or #labels > 0 or workspace == "1" or workspace == "2" or workspace == "3"
					item:set({
						drawing = visible,
						icon = { color = active and colors.black or (#labels > 0 and colors.white or colors.grey) },
						label = {
							string = table.concat(labels, " "),
							drawing = #labels > 0,
							color = active and colors.black or colors.white,
						},
						background = { color = active and colors.orange or colors.bg1 },
					})
				end
			end
		)
	end)
end

local state = sbar.add("item", "workspace_state", { drawing = false, updates = true })
state:subscribe(
	{ "forced", "aerospace_workspace_change", "front_app_switched", "space_windows_change", "system_woke" },
	refresh
)
refresh()
