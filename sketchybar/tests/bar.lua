-- Run with lua sketchybar/tests/bar.lua; no system commands are run.
local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
local settings = assert(loadfile(root .. "/settings.lua"))()
local colors = assert(loadfile(root .. "/colors.lua"))()
local total = 0

local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

local function capture(module, method)
	local values
	local modules = {
		settings = settings,
		colors = colors,
		sketchybar = {
			[method] = function(config)
				values = config
			end,
		},
	}
	local env = setmetatable({
		require = function(name)
			return assert(modules[name], "Unexpected require: " .. name)
		end,
	}, { __index = _G })
	assert(loadfile(root .. "/" .. module .. ".lua", "t", env))()
	return assert(values, "Missing configuration")
end

test("bar is a continuous tinted 26px strip with no outer gaps", function()
	local bar = capture("bar", "bar")
	equal(bar.position, "top")
	equal(bar.height, 26)
	equal(bar.margin, 0)
	equal(bar.y_offset, 0)
	equal(bar.padding_left, 8)
	equal(bar.padding_right, 8)
	equal(bar.corner_radius, 0)
	equal(bar.border_width, 0)
	equal(bar.blur_radius, 20)
	equal(bar.shadow, false)
	equal(bar.color & 0xffffff, colors.black & 0xffffff)
	equal(bar.color >> 24, 0xb3)
	equal(bar.display, "all")
end)

test("square bar items preserve the existing popup frames and spacing", function()
	local defaults = capture("default", "default")
	equal(defaults.background.height, settings.bar.height)
	equal(defaults.background.corner_radius, 0)
	equal(defaults.background.color, colors.transparent)
	equal(defaults.popup.padding, 14)
	equal(defaults.popup.gap, 6)
	equal(defaults.popup.background.border_width, 2)
	equal(defaults.popup.background.corner_radius, 4)
	equal(defaults.popup.background.border_color, colors.accent)
	equal(defaults.popup.background.color >> 24, 0xff)
end)

test("entry point loads the panels without adding floating group brackets", function()
	local loaded = {}
	local sbar = {
		begin_config = function() end,
		end_config = function() end,
		exec = function() end,
		event_loop = function() end,
	}
	local env = setmetatable({
		package = { path = "", cpath = "" },
		os = {
			getenv = function()
				return root
			end,
		},
		require = function(name)
			loaded[name] = true
			return sbar
		end,
	}, { __index = _G })
	assert(loadfile(root .. "/init.lua", "t", env))()
	equal(loaded.groups, nil)
	for _, name in ipairs({
		"bar",
		"default",
		"items.workspaces",
		"items.calendar",
		"items.widgets.battery",
		"items.widgets.volume",
		"items.widgets.wifi",
		"items.widgets.bluetooth",
		"items.panel_keys",
	}) do
		equal(loaded[name], true)
	end
end)

test("yabai reserves the bar height plus a 10px gap above app windows", function()
	local file = assert(io.open(root .. "/../yabai/yabairc"))
	local config = file:read("*a")
	file:close()
	local height = assert(config:match("yabai %-m config external_bar all:(%d+):0"))
	equal(tonumber(height), settings.bar.height)
	local padding = assert(config:match("yabai %-m config top_padding (%d+)"))
	equal(tonumber(padding), 10)
end)

print(total .. " bar tests passed")
