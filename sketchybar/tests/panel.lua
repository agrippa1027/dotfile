-- Pure styling and event-routing tests; no SketchyBar or system commands run.
local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
package.path = root .. "/?.lua;" .. package.path
local ui = require("lib.panel")
local colors = require("colors")
local settings = require("settings")
local count = 0
local function test(name, run)
	run()
	count = count + 1
	print("ok " .. count .. " - " .. name)
end
local function item()
	return {
		handlers = {},
		set = function(self, values)
			for key, value in pairs(values) do
				self[key] = value
			end
		end,
		subscribe = function(self, event, handler)
			self.handlers[event] = handler
		end,
	}
end

test("hover restores the selected background without changing content", function()
	local row = item()
	row.label = "Cloudflare"
	local state = ui.action(row, { selected = true })
	assert(row.background.color == colors.panel.selected)
	row.handlers["mouse.entered"]()
	assert(row.background.color == colors.panel.hover)
	row.handlers["mouse.exited"]()
	assert(row.background.color == colors.panel.selected and row.label == "Cloudflare")
	state:select(false)
	assert(row.background.color == colors.panel.control)
end)

test("disabled controls have no interactive chrome", function()
	local row = item()
	local state = ui.action(row, { enabled = false })
	row.handlers["mouse.entered"]()
	assert(row.background.color == colors.transparent and row.background.border_width == 0)
	state:enable(true)
	assert(row.background.color == colors.panel.hover)
	state:reset()
	assert(row.background.color == colors.panel.control)
end)

test("controls and headings do not add phantom grid padding", function()
	local row = item()
	ui.action(row)
	assert(row.background.height == settings.popup.control_height)
	assert(row.background.padding_left == 0 and row.background.padding_right == 0)
	ui.heading(row)
	assert(row.label.font.size == 14 and row.background.height == 42)
	ui.section(row)
	assert(row.label.font.size == 10 and row.label.color == colors.grey)
	assert(row.background.padding_left == 0 and row.background.padding_right == 0)
end)

local events, receiver, toggled, closed = {}, item(), {}, 0
local modules = {
	sketchybar = {
		add = function(kind, name, options)
			if kind == "event" then
				events[name] = true
			else
				assert(name == "panel_keys" and not options.drawing and options.updates)
				return receiver
			end
		end,
	},
	["lib.popup"] = {
		toggle = function(name)
			toggled[#toggled + 1] = name
		end,
		close_all = function()
			closed = closed + 1
		end,
	},
}
assert(loadfile(
	root .. "/items/panel_keys.lua",
	"t",
	setmetatable({
		require = function(name)
			return assert(modules[name])
		end,
	}, { __index = _G })
))()

test("hotkeys register hidden receivers for all five existing panels", function()
	assert(events.omarchy_panel_toggle and events.omarchy_panel_close)
	for alias, name in pairs({
		audio = "widgets.volume",
		network = "widgets.wifi",
		bluetooth = "widgets.bluetooth",
		power = "widgets.battery",
		calendar = "calendar",
	}) do
		receiver.handlers.omarchy_panel_toggle({ PANEL = alias })
		assert(toggled[#toggled] == name)
	end
end)

test("unknown panel requests are ignored and close uses the shared lifecycle", function()
	local before = #toggled
	receiver.handlers.omarchy_panel_toggle({ PANEL = "not-a-panel" })
	receiver.handlers.omarchy_panel_toggle({})
	assert(#toggled == before)
	receiver.handlers.omarchy_panel_close({})
	assert(closed == 1)
end)

print("PASS: " .. count .. " panel styling and hotkey tests")
