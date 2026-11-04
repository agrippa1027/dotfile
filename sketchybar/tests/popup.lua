local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
local function fixture()
	local items, commands = {}, {}
	local sbar = {
		exec = function(command)
			commands[#commands + 1] = command
		end,
	}
	local popup = assert(loadfile(root .. "/lib/popup.lua", "t", {
		require = function(name)
			if name == "colors" then
				return { transparent = 0, panel = { selected = 1 } }
			end
			return sbar
		end,
		type = type,
	}))()
	local function owner(name)
		local item = { name = name, opened = false, handlers = {} }
		function item:query()
			return self.missing and {} or { popup = { drawing = self.opened and "on" or "off" } }
		end
		function item:set(values)
			self.opened = values.popup.drawing
			self.background = values.background
		end
		function item:subscribe(events, callback)
			self.handlers[events] = callback
		end
		items[name] = item
		return item
	end
	return popup, owner, commands
end
local count = 0
local function test(name, fn)
	fn()
	count = count + 1
	print("ok " .. count .. " - " .. name)
end

test("missing startup queries are safely treated as closed", function()
	local popup, owner = fixture()
	local item = owner("one")
	item.missing = true
	assert(not popup.is_open(item))
	item.query = function()
		return nil
	end
	assert(not popup.is_open(item))
end)
test("opening and closing call lifecycle hooks once", function()
	local popup, owner = fixture()
	local item, opened, closed = owner("one"), 0, 0
	local panel = popup.bind(item, {
		on_open = function()
			opened = opened + 1
		end,
		on_close = function()
			closed = closed + 1
		end,
	})
	panel:toggle()
	assert(item.opened and opened == 1)
	panel:close()
	panel:close()
	assert(not item.opened and closed == 1)
end)
test("opening another panel closes the first and its telemetry", function()
	local popup, owner = fixture()
	local a, b, closed = owner("one"), owner("two"), 0
	local first = popup.bind(a, {
		on_close = function()
			closed = closed + 1
		end,
	})
	local second = popup.bind(b)
	first:toggle()
	second:toggle()
	assert(not a.opened and b.opened and closed == 1)
end)
test("logical active state stops telemetry despite a transient missing query", function()
	local popup, owner = fixture()
	local item, closed = owner("one"), 0
	local panel = popup.bind(item, {
		on_close = function()
			closed = closed + 1
		end,
	})
	panel:toggle()
	item.missing = true
	panel:close()
	assert(not item.opened and closed == 1)
end)
test("right click settings does not start popup telemetry", function()
	local popup, owner, commands = fixture()
	local item, opened = owner("one"), 0
	popup.bind(item, {
		settings_command = "open settings",
		on_open = function()
			opened = opened + 1
		end,
	})
	item.handlers["mouse.clicked"]({ BUTTON = "right" })
	assert(commands[1] == "open settings" and opened == 0 and not item.opened)
end)
test("named shortcuts use the same single-panel lifecycle and active styling", function()
	local popup, owner = fixture()
	local a, b = owner("one"), owner("two")
	popup.bind(a)
	popup.bind(b)
	assert(not popup.toggle("unknown"))
	assert(popup.toggle("one") and a.opened and a.background.color == 1)
	popup.toggle("two")
	assert(not a.opened and a.background.color == 0 and b.opened)
	popup.close_all()
	assert(not b.opened and b.background.color == 0)
	popup.close_all()
end)
test("repeating a shortcut closes even during a missing native query", function()
	local popup, owner = fixture()
	local item = owner("one")
	popup.bind(item)
	popup.toggle("one")
	item.missing = true
	popup.toggle("one")
	assert(not item.opened)
end)
print("PASS: " .. count .. " popup lifecycle tests")
