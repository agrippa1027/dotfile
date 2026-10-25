-- Run with lua path/to/sketchybar/tests/workspaces.lua; no system commands are run.
local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
local colors = { black = "black", white = "white", grey = "grey", accent = "accent", transparent = "transparent" }
local settings = { workspaces = { small_group_edge_padding = 18 } }
local spaces = {
	{ index = 1, display = 1, label = "ws-1", ["has-focus"] = true },
	{ index = 2, display = 1, label = "ws-2" },
	{ index = 3, display = 2, label = "ws-3" },
}
local windows = {
	{ space = 1, app = "Alpha" },
	{ space = 1, app = "Alpha" },
	{ space = 1, app = "Beta" },
	{ space = 2, app = "Unknown" },
}

local function equal(actual, expected, message)
	assert(
		actual == expected,
		(message or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	)
end

local function fixture()
	local mock = { now = 1000, commands = {}, items = {} }
	local sbar = {}
	function sbar.add(kind, name, config)
		if kind == "event" then
			return
		end
		local item = { config = config, handlers = {}, updates = 0 }
		function item:subscribe(events, callback)
			for _, event in ipairs(type(events) == "table" and events or { events }) do
				self.handlers[event] = callback
			end
		end
		function item:set(values)
			self.updates = self.updates + 1
			self.values = values
		end
		mock.items[name] = item
		return item
	end
	function sbar.exec(command, callback)
		mock.commands[#mock.commands + 1] = { command = command, callback = callback }
	end
	local modules = {
		sketchybar = sbar,
		colors = colors,
		settings = settings,
		["lib.utils"] = assert(loadfile(root .. "/lib/utils.lua"))(),
		["vendor.app-font.icon_map"] = { Alpha = ":alpha:", Beta = ":beta:" },
	}
	local env = setmetatable({
		os = {
			time = function()
				return mock.now
			end,
		},
		require = function(name)
			return assert(modules[name], "Unexpected require: " .. name)
		end,
	}, { __index = _G })
	assert(loadfile(root .. "/items/workspaces.lua", "t", env))()
	function mock:fire(event)
		assert(self.items.workspace_state.handlers[event or "yabai_workspace_change"], "Missing event")()
	end
	function mock:reply(index, result, status)
		local call = assert(self.commands[index], "Missing command " .. index)
		assert(not call.replied, "Callback already delivered")
		call.replied = true
		assert(call.callback)(result, status or 0)
	end
	function mock:expect(index, kind)
		equal(self.commands[index].command, "/opt/homebrew/bin/yabai -m query --" .. kind)
	end
	return mock
end

local passed = 0
local function test(name, run)
	run()
	passed = passed + 1
	print("ok " .. passed .. " - " .. name)
end

local function ready()
	local mock = fixture()
	mock:reply(1, spaces)
	mock:reply(2, windows)
	return mock
end

test("initial refresh queries spaces then windows and preserves workspace rendering", function()
	local mock = ready()
	equal(#mock.commands, 2)
	mock:expect(1, "spaces")
	mock:expect(2, "windows")
	local first = mock.items["workspace.1"].values
	equal(first.label.string, ":alpha: :beta:", "sorted, deduplicated apps")
	equal(first.background.color, colors.accent)
	equal(first.icon.color, colors.black)
	equal(first.display, 1)
	equal(first.padding_left, 18)
	equal(mock.items["workspace.2"].values.label.string, ":default:")
	equal(mock.items["workspace.3"].values.label.drawing, false)
	equal(mock.items["workspace.4"].values.drawing, false)
end)

test("20 events during the space query coalesce into one follow-up", function()
	local mock = fixture()
	for _ = 1, 20 do
		mock:fire()
	end
	equal(#mock.commands, 1)
	mock:reply(1, spaces)
	equal(#mock.commands, 2)
	mock:expect(2, "spaces")
	mock:reply(2, spaces)
	mock:reply(3, windows)
	equal(#mock.commands, 3)
	equal(mock.items["workspace.1"].updates, 1)
end)

test("events during the window query discard stale rendering and queue one follow-up", function()
	local mock = fixture()
	mock:reply(1, spaces)
	for _ = 1, 20 do
		mock:fire()
	end
	equal(#mock.commands, 2)
	mock:reply(2, windows)
	equal(mock.items["workspace.1"].updates, 0)
	mock:expect(3, "spaces")
	mock:reply(3, spaces)
	mock:reply(4, windows)
	equal(#mock.commands, 4)
	equal(mock.items["workspace.1"].updates, 1)
end)

test("forced and native window events use the same coalesced reader", function()
	local mock = ready()
	mock:fire("forced")
	mock:fire("space_windows_change")
	equal(#mock.commands, 3)
	mock:reply(3, spaces)
	mock:reply(4, spaces)
	mock:reply(5, {})
	equal(mock.items["workspace.1"].values.label.drawing, false)
	for _, event in ipairs({ "space_change", "display_change", "front_app_switched", "system_woke" }) do
		equal(mock.items.workspace_state.handlers[event], nil, "duplicate native subscription")
	end
end)

for _, case in ipairs({
	{ name = "failed space query", value = spaces, status = 1 },
	{ name = "non-table spaces", value = "invalid" },
	{ name = "empty spaces", value = {} },
	{ name = "malformed space entry", value = { { index = "bad", display = 1 } } },
}) do
	test(case.name .. " releases the reader", function()
		local mock = fixture()
		mock:reply(1, case.value, case.status)
		equal(#mock.commands, 1)
		mock:fire()
		mock:reply(2, spaces)
		mock:reply(3, windows)
		equal(mock.items["workspace.1"].updates, 1)
	end)
end

for _, case in ipairs({
	{ name = "failed window query", value = windows, status = 1 },
	{ name = "non-table windows", value = "invalid" },
	{ name = "malformed window entry", value = { { space = 1 } } },
}) do
	test(case.name .. " releases the reader", function()
		local mock = fixture()
		mock:reply(1, spaces)
		mock:reply(2, case.value, case.status)
		mock:fire()
		mock:reply(3, spaces)
		mock:reply(4, windows)
		equal(mock.items["workspace.1"].updates, 1)
	end)
end

test("an error with pending events still starts exactly one follow-up", function()
	local mock = fixture()
	mock:fire()
	mock:reply(1, nil, 1)
	equal(#mock.commands, 2)
	mock:reply(2, spaces)
	mock:reply(3, windows)
	equal(mock.items["workspace.1"].updates, 1)
end)

test("lost space callbacks recover after 65 seconds and late results are ignored", function()
	local mock = fixture()
	mock.now = 1064
	mock:fire()
	equal(#mock.commands, 1)
	mock.now = 1065
	mock:fire()
	equal(#mock.commands, 2)
	mock:reply(1, spaces)
	equal(#mock.commands, 2)
	mock:reply(2, spaces)
	mock:reply(3, windows)
	equal(mock.items["workspace.1"].updates, 1)
end)

test("lost window callbacks cannot overwrite a recovered refresh", function()
	local mock = fixture()
	mock:reply(1, spaces)
	mock.now = 1065
	mock:fire()
	mock:reply(3, spaces)
	mock:reply(4, windows)
	mock:reply(2, {})
	equal(mock.items["workspace.1"].values.label.string, ":alpha: :beta:")
	equal(mock.items["workspace.1"].updates, 1)
end)

test("starting the window query renews the command deadline", function()
	local mock = fixture()
	mock.now = 1050
	mock:reply(1, spaces)
	mock.now = 1065
	mock:fire()
	equal(#mock.commands, 2)
	mock.now = 1114
	mock:fire()
	equal(#mock.commands, 2)
	mock.now = 1115
	mock:fire()
	equal(#mock.commands, 3)
	mock:reply(3, spaces)
	mock:reply(4, windows)
	mock:reply(2, {})
	equal(mock.items["workspace.1"].updates, 1)
end)

test("workspace clicks use the latest successfully rendered indices", function()
	local mock = ready()
	mock:fire()
	mock:reply(3, { { index = 7, display = 2, label = "ws-1", ["has-focus"] = true } })
	mock:reply(4, {})
	mock.items["workspace.1"].handlers["mouse.clicked"]()
	equal(mock.commands[5].command, "/opt/homebrew/bin/yabai -m space --focus '7'")
	mock.items["workspace.2"].handlers["mouse.clicked"]()
	equal(#mock.commands, 5)
end)

print(passed .. " workspace tests passed")
