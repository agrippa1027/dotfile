-- All commands, dialogs, time and hardware are mocked.
local root = (arg[0]:match("^(.*)/") or ".") .. "/.."
package.path = root .. "/?.lua;" .. package.path
local colors, settings = require("colors"), require("settings")
local controls = require("lib.bluetooth_controls")
local defaults = "/usr/bin/defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null"
local A, B, C = "aa:bb:cc:dd:ee:01", "aa:bb:cc:dd:ee:02", "aa:bb:cc:dd:ee:03"
local function dev(address, name, connected, paired)
	return { address = address, name = name, connected = connected, paired = paired }
end
local function merge(target, values)
	for k, v in pairs(values) do
		if type(v) == "table" then
			target[k] = target[k] or {}
			merge(target[k], v)
		elseif (k == "label" or k == "icon") and type(target[k]) == "table" then
			target[k].string = v
		else
			target[k] = v
		end
	end
end
local function fixture()
	local env = { now = 1000, items = {}, commands = {} }
	local sbar = {}
	function sbar.add(_, name, properties)
		local item = { name = name, properties = properties, handlers = {} }
		function item:set(values)
			merge(self.properties, values)
		end
		function item:query()
			return { popup = { drawing = self.properties.popup and self.properties.popup.drawing and "on" or "off" } }
		end
		function item:subscribe(events, callback)
			for _, event in ipairs(type(events) == "table" and events or { events }) do
				self.handlers[event] = callback
			end
		end
		env.items[name] = item
		return item
	end
	function sbar.exec(command, callback)
		env.commands[#env.commands + 1] = { command = command, callback = callback }
	end
	local modules = {
		sketchybar = sbar,
		colors = colors,
		settings = settings,
		icons = { bluetooth = "BT" },
		["lib.utils"] = require("lib.utils"),
		["lib.bluetooth_controls"] = controls,
	}
	local scope = setmetatable({
		os = {
			time = function()
				return env.now
			end,
		},
		require = function(name)
			return assert(modules[name], name)
		end,
	}, { __index = _G })
	modules["lib.panel"] = assert(loadfile(root .. "/lib/panel.lua", "t", scope))()
	modules["lib.popup"] = assert(loadfile(root .. "/lib/popup.lua", "t", scope))()
	local audio = sbar.add("item", "widgets.volume", { popup = { drawing = false } })
	modules["lib.popup"].bind(audio, {
		on_open = function()
			env.audio_opened = true
		end,
	})
	env.widget = assert(loadfile(root .. "/items/widgets/bluetooth.lua", "t", scope))()
	function env:item(suffix)
		return assert(self.items["widgets.bluetooth" .. (suffix and "." .. suffix or "")], suffix)
	end
	function env:fire(suffix, event, values)
		assert(self:item(suffix).handlers[event], suffix or "owner")(values or {})
	end
	function env:click(suffix)
		self:fire(suffix, "mouse.clicked", { BUTTON = "left" })
	end
	function env:take(fragment)
		for _, request in ipairs(self.commands) do
			if not request.replied and request.command:find(fragment, 1, true) then
				request.replied = true
				return request
			end
		end
		error("Missing command: " .. fragment)
	end
	function env:reply(fragment, value, code)
		local request = self:take(fragment)
		assert(request.callback, fragment)(value, code or 0)
	end
	function env:count(fragment)
		local count = 0
		for _, r in ipairs(self.commands) do
			if r.command:find(fragment, 1, true) then
				count = count + 1
			end
		end
		return count
	end
	function env:label(suffix)
		return self:item(suffix).properties.label.string
	end
	function env:message()
		return self:label("message")
	end
	function env:inventory(remembered, live)
		self:reply("--power", "1")
		self:reply("--paired", remembered or { dev(A, "Buds", false, true), dev(B, "Keyboard", true, true) })
		self:reply("--connected", live or { dev(B, "Keyboard", true, true) })
	end
	function env:open()
		self:reply(defaults, "1")
		self:click()
		self:inventory()
		self:reply("system_profiler", nil, 1)
	end
	return env
end
local total = 0
local function test(name, fn)
	fn()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end
local function equal(a, b)
	assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a))
end

test("collapsed reads are cheap, coalesced and never scan or mutate", function()
	local e = fixture()
	equal(#e.commands, 1)
	equal(e.commands[1].command, defaults)
	for _ = 1, 20 do
		e:fire(nil, "routine")
	end
	equal(#e.commands, 1)
	e:reply(defaults, "1")
	equal(#e.commands, 2)
	e:reply(defaults, "0")
	equal(e:count("--inquiry"), 0)
	equal(e:count("--connect "), 0)
	equal(e.widget.properties.update_freq, 60)
end)
test("opening during a startup read queues a detailed refresh", function()
	local e = fixture()
	e:click()
	equal(e:count("--paired"), 0)
	e:reply(defaults, "1")
	e:inventory()
	e:reply("system_profiler", nil, 1)
	equal(e:label("status"), "1 connected · 1 remembered")
end)
test("connected and remembered devices expose explicit actions with shared geometry", function()
	local e = fixture()
	e:open()
	equal(e:label("connected.1.info"), "Keyboard")
	equal(e:label("connected.1.action"), "Disconnect")
	equal(e:label("known.1.info"), "Buds")
	equal(e:label("known.1.action"), "Connect")
	equal(e:item("connected.1.action").properties.cursor, "pointer")
	equal(e.widget.properties.popup.columns, 6)
	for _, suffix in ipairs({ "connected.1.info", "connected.1.action", "connected.1.forget" }) do
		local p = e:item(suffix).properties
		equal(p.background.padding_left, 0)
		equal(p.background.padding_right, 0)
	end
	equal(e:item("timer").properties.update_freq, 10)
end)
test("a powered-off radio still offers Turn on without querying connected devices", function()
	local e = fixture()
	e:reply(defaults, "0")
	e:click()
	e:reply("--power", "0")
	equal(e:label("power"), "Turn Bluetooth on")
	equal(e:item("power").properties.cursor, "pointer")
	equal(e:count("--connected"), 0)
	equal(e:count("--paired"), 0)
end)
test("connect is serialized, targets a validated captured address and verifies readback", function()
	local e = fixture()
	e:open()
	e:click("known.1.action")
	e:click("connected.1.action")
	equal(e:count("--paired"), 2)
	equal(e:label("known.1.action"), "Connecting…")
	e:reply("--paired", { dev(A, "Buds", false, true) })
	equal(e:take("--connect").command, controls.command("connect", A) .. " 2>/dev/null")
	-- Complete the consumed mutation callback manually.
	local r = e.commands[#e.commands]
	r.callback("", 0)
	e:reply("--paired", { dev(A, "Buds", true, true) })
	equal(e:message(), "Device connected")
end)
test("inventory captured before an action cannot replace its stable target or verified state", function()
	local e = fixture()
	e:open()
	e:fire(nil, "forced")
	local stale = e:take("--power")
	e:click("known.1.action")
	local preflight = e:take("--paired")
	e:fire(nil, "forced") -- queued until the mutation settles
	stale.callback("0", 0)
	equal(e:label("known.1.info"), "Buds")
	preflight.callback({ dev(A, "Buds", false, true) }, 0)
	local write = e:take("--connect")
	assert(write.command:find(A, 1, true))
	assert(not write.command:find(C, 1, true))
	write.callback("", 0)
	e:reply("--paired", { dev(A, "Buds", true, true) })
	equal(e:message(), "Device connected")
end)
test("multipoint earbuds use authoritative address snapshots for display and disconnect readback", function()
	local e = fixture()
	e:reply(defaults, "1")
	e:click()
	-- Report mode sees the connected multipoint device even if native API
	-- enumeration omits it. Address spelling is normalized, never name-matched.
	e:inventory({ dev(A:upper(), "Buds", true, true) }, {})
	e:reply("system_profiler", nil, 1)
	equal(e:label("connected.1.action"), "Disconnect")
	equal(e:item("known.1.info").properties.drawing, false)
	e:click("connected.1.action")
	local preflight = e:take("--paired")
	assert(preflight.command:find("BLUEUTIL_USE_SYSTEM_PROFILER=1", 1, true))
	preflight.callback({ dev(A:upper(), "Buds", true, true) }, 0)
	local write = e:take("--disconnect")
	assert(write.command:find(A, 1, true))
	write.callback("", 0)
	e:reply("--paired", { dev(A:upper(), "Buds", false, true) })
	equal(e:message(), "Device disconnected")
	equal(e:count("--info"), 0)
end)
test("failed or changed preflight cannot issue a device write", function()
	for _, raw in ipairs({
		dev(C, "Other", false, true),
		dev(A, "Buds", false, false),
		{ address = A, name = "Buds", paired = true },
	}) do
		local e = fixture()
		e:open()
		e:click("known.1.action")
		e:reply("--paired", { raw })
		equal(e:count("--connect "), 0)
	end
end)
test("lagging disconnect snapshots settle without repeating the mutation", function()
	local e = fixture()
	e:open()
	e:click("connected.1.action")
	e:reply("--paired", { dev(B, "Keyboard", true, true) })
	e:reply("--disconnect", "", 0)
	e:reply("--paired", { dev(B, "Keyboard", true, true) })
	equal(e:label("connected.1.action"), "Disconnecting…")
	local retry = e:take("--paired")
	assert(retry.command:find("/bin/sleep 0.5; ", 1, true))
	retry.callback({ dev(B:upper(), "Keyboard", false, true) }, 0)
	equal(e:message(), "Device disconnected")
	equal(e:count("--disconnect "), 1)
end)
test("connect and forget readback also tolerate delayed authoritative snapshots", function()
	local e = fixture()
	e:open()
	e:click("known.1.action")
	e:reply("--paired", { dev(A, "Buds", false, true) })
	e:reply("--connect", "", 0)
	e:reply("--paired", { dev(A, "Buds", false, true) })
	e:reply("--paired", { dev(A, "Buds", false, true) })
	e:reply("--paired", { dev(A, "Buds", true, true) })
	equal(e:message(), "Device connected")
	equal(e:count("--connect "), 1)
	local f = fixture()
	f:open()
	f:click("known.1.forget")
	f:reply("osascript", "Forget")
	f:reply("--paired", { dev(A, "Buds", false, true) })
	f:reply("--unpair", "", 0)
	f:reply("--paired", { dev(A, "Buds", false, true) })
	f:reply("--paired", {})
	equal(f:message(), "Device forgotten")
	equal(f:count("--unpair "), 1)
end)
test("permanent readback mismatch is bounded and never repeats the write", function()
	local e = fixture()
	e:open()
	e:click("connected.1.action")
	e:reply("--paired", { dev(B, "Keyboard", true, true) })
	e:reply("--disconnect", "", 0)
	for _ = 1, 10 do
		e:reply("--paired", { dev(B, "Keyboard", true, true) })
	end
	assert(e:message():find("could not be verified", 1, true))
	equal(e:count("--disconnect "), 1)
	equal(e:count("/bin/sleep 0.5; "), 9)
end)
test("readback failure stops retries and a superseded delayed callback is ignored", function()
	local e = fixture()
	e:open()
	e:click("known.1.action")
	e:reply("--paired", { dev(A, "Buds", false, true) })
	e:reply("--connect", "", 0)
	e:reply("--paired", nil, 1)
	assert(e:message():find("could not be verified", 1, true))
	equal(e:count("/bin/sleep"), 0)
	local f = fixture()
	f:open()
	f:click("known.1.action")
	f:reply("--paired", { dev(A, "Buds", false, true) })
	f:reply("--connect", "", 0)
	f:reply("--paired", { dev(A, "Buds", false, true) })
	local delayed = f:take("--paired")
	f.now = f.now + 65
	f:fire("timer", "routine")
	local message = f:message()
	delayed.callback({ dev(A, "Buds", true, true) }, 0)
	equal(f:message(), message)
	equal(f:count("--connect "), 1)
end)
test("failed writes report errors and do not perform optimistic state changes", function()
	local e = fixture()
	e:open()
	e:click("known.1.action")
	e:reply("--paired", { dev(A, "Buds", false, true) })
	e:reply("--connect", "denied", 1)
	assert(e:message():find("failed", 1, true))
	equal(e:label("known.1.action"), "Connect")
	e:click("known.1.action")
	equal(e:item("message").properties.drawing, false)
end)
test("forget cancellation has no write and names are safe in native dialog scripts", function()
	local e = fixture()
	e:open()
	e:fire(nil, "forced")
	local name = 'Buds "quoted"\\name\n$(touch /tmp/nope)'
	e:inventory({ dev(A, name, false, true) }, {})
	e:click("known.1.forget")
	local prompt = e:take("osascript")
	assert(prompt.command:find('\\"quoted\\"', 1, true))
	assert(prompt.command:find("$(touch /tmp/nope)", 1, true))
	assert(prompt.command:find("-e '", 1, true))
	prompt.callback("", 1)
	equal(e:count("--unpair"), 0)
	equal(e:count("--paired"), 2)
end)
test("native Forget confirmation survives popup dismissal and verifies removal", function()
	local e = fixture()
	e:open()
	e:click("known.1.forget")
	e:fire(nil, "mouse.exited.global")
	e:reply("osascript", "Forget\n")
	e:reply("--paired", { dev(A, "Buds", false, true) })
	e:reply("--unpair", "", 0)
	e:reply("--paired", { dev(B, "Keyboard", true, true) })
	equal(e:item("timer").properties.update_freq, 0)
	equal(e:count("--unpair"), 1)
end)
test("power off requires confirmation and exact state verification", function()
	local e = fixture()
	e:open()
	e:click("power")
	local prompt = e:take("osascript")
	assert(prompt.command:find("keyboards, mice", 1, true))
	prompt.callback("Turn off", 0)
	e:reply("--power", "1")
	e:reply("--power 0", "", 0)
	e:reply("--power", "0")
	equal(e:message(), "Bluetooth power updated")
	equal(e:label("power"), "Turn Bluetooth on")
end)
test("power-on readback mismatch stays an error", function()
	local e = fixture()
	e:reply(defaults, "0")
	e:click()
	e:reply("--power", "0")
	e:reply("system_profiler", nil, 1)
	e:click("power")
	e:reply("--power", "0")
	e:reply("--power 1", "", 0)
	e:reply("--power", "0")
	equal(e:message(), "Power change could not be verified")
end)
test("nearby scan is opt-in and pairs through native Settings without hidden PIN prompts", function()
	local e = fixture()
	e:open()
	equal(e:count("--inquiry"), 0)
	e:click("scan")
	equal(e:label("scan"), "Scanning…")
	e:reply("--inquiry", { dev(C, "Speaker", false, false) })
	equal(e:label("nearby.1.info"), "Speaker")
	equal(e:label("nearby.1.action"), "Pair in Settings")
	equal(e:item("nearby.1.forget").properties.cursor, "default")
	e:click("nearby.1.action")
	equal(e.commands[#e.commands].command, settings.commands.bluetooth)
	equal(e:count("--pair "), 0)
end)
test("close stops polling and ignores late scan results across reopen", function()
	local e = fixture()
	e:open()
	e:click("scan")
	local scan = e:take("--inquiry")
	e:fire(nil, "mouse.exited.global")
	equal(e:item("timer").properties.update_freq, 0)
	e:click()
	e:inventory()
	scan.callback({ dev(C, "Old nearby", false, false) }, 0)
	equal(e:item("nearby.1.info").properties.drawing, false)
end)
test("closing cancels preflight but an executing mutation can finish hidden", function()
	local e = fixture()
	e:open()
	e:click("known.1.action")
	local old = e:take("--paired")
	e:fire(nil, "mouse.exited.global")
	old.callback({ dev(A, "Buds", false, true) }, 0)
	equal(e:count("--connect "), 0)
	local f = fixture()
	f:open()
	f:click("known.1.action")
	f:reply("--paired", { dev(A, "Buds", false, true) })
	f:fire(nil, "mouse.exited.global")
	f:reply("--connect", "", 0)
	f:reply("--paired", { dev(A, "Buds", true, true) })
	equal(f:item("message").properties.drawing, false)
end)
test("lost scan and action callbacks recover on the visible watchdog", function()
	local e = fixture()
	e:open()
	e:click("scan")
	local old = e:take("--inquiry")
	e.now = e.now + 65
	e:fire("timer", "routine")
	equal(e:label("scan"), "Scan nearby · 8s")
	old.callback({ dev(C, "Late", false, false) }, 0)
	equal(e:item("nearby.1.info").properties.drawing, false)
	local f = fixture()
	f:open()
	f:click("known.1.action")
	local stale = f:take("--paired")
	f.now = f.now + 65
	f:fire("timer", "routine")
	stale.callback({ dev(A, "Buds", false, true) }, 0)
	equal(f:count("--connect "), 0)
	assert(f:message():find("timed out", 1, true))
end)
test("lost reads recover and old reports cannot replace current inventory", function()
	local e = fixture()
	e:reply(defaults, "1")
	e:click()
	local old = e:take("--power")
	e.now = e.now + 65
	e:fire("timer", "routine")
	e:inventory({ dev(C, "Fresh", false, true) }, {})
	old.callback("0", 0)
	equal(e:label("known.1.info"), "Fresh")
end)
test("profiler fallback distinguishes remembered devices and disables actions without valid backend", function()
	local e = fixture()
	e:reply(defaults, "1")
	e:click()
	e:reply("--power", "", 127)
	-- The first profiler request is optional battery enrichment; the next is fallback.
	e:reply("system_profiler", nil, 1)
	e:reply("system_profiler", {
		SPBluetoothDataType = {
			{
				controller_properties = { controller_state = "attrib_on" },
				device_connected = { { Mouse = { device_address = "redacted" } } },
				device_not_connected = { { Speaker = { device_address = "redacted" } } },
			},
		},
	})
	equal(e:label("status"), "1 connected · 1 remembered")
	equal(e:label("connected.1.info"), "Mouse")
	equal(e:label("known.1.info"), "Speaker")
	equal(e:item("connected.1.action").properties.cursor, "default")
	equal(e:item("power").properties.cursor, "default")
	e:click("connected.1.action")
	equal(e:count("--disconnect"), 0)
end)
test("battery enrichment is reported only for matching real addresses", function()
	local e = fixture()
	e:reply(defaults, "1")
	e:click()
	e:inventory()
	e:reply("system_profiler", {
		SPBluetoothDataType = {
			{
				controller_properties = { controller_state = "attrib_on" },
				device_connected = { { Keyboard = { device_address = B, device_batteryLevelMain = "42%" } } },
			},
		},
	})
	equal(e:label("connected.1.info"), "Keyboard · 42%")
end)
test("Bluetooth LE accessories use native Settings instead of unsupported direct controls", function()
	local e = fixture()
	e:reply(defaults, "1")
	e:click()
	e:inventory()
	e:reply("system_profiler", {
		SPBluetoothDataType = {
			{
				controller_properties = { controller_state = "attrib_on" },
				device_connected = { { Keyboard = { device_services = "0x400000 < BLE >" } } },
			},
		},
	})
	equal(e:label("connected.1.action"), "Settings ↗")
	equal(e:item("connected.1.forget").properties.cursor, "default")
	e:click("connected.1.forget")
	equal(e:count("--unpair"), 0)
	e:click("connected.1.action")
	equal(e:count(settings.commands.bluetooth), 1)
	equal(e:count("--disconnect"), 0)
end)
test("bounded sections advertise overflow and footer routes share lifecycle", function()
	local e = fixture()
	e:open()
	e:fire(nil, "forced")
	local list = {}
	for i = 1, 6 do
		list[#list + 1] = dev(string.format("aa:bb:cc:dd:ee:%02x", i), "Device " .. i, false, true)
	end
	e:inventory(list, {})
	assert(e:label("known.heading"):find("MORE IN SETTINGS", 1, true))
	e:click("audio")
	equal(e.audio_opened, true)
	equal(e:item("timer").properties.update_freq, 0)
end)
print("PASS: " .. total .. " Bluetooth panel tests")
