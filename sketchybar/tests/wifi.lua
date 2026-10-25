-- Run with lua path/to/sketchybar/tests/wifi.lua from any working directory.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. script_dir .. "../?/init.lua;" .. package.path

local real_time = os.time
local real_execute = os.execute
local real_popen = io.popen
local real_sketchybar_loader = package.preload.sketchybar
local function no_system_commands()
	error("Real system commands are disabled in Wi-Fi tests", 2)
end
os.execute = no_system_commands
io.popen = no_system_commands
package.loaded.sketchybar = nil
package.preload.sketchybar = function()
	error("Install the sbar mock before loading the Wi-Fi widget")
end

local colors = require("colors")
local icons = require("icons")
local total = 0
local defaults = {
	discovery = "Hardware Port: Wi-Fi\nDevice: en0\n",
	power = "Wi-Fi Power (en0): On\n",
	summary = "Interface: en0\n  LinkStatusActive : TRUE\n  SSID : Test Wi-Fi\n  Router : 192.168.1.1\n",
	link = "en0: flags=8863\n\tstatus: active\n",
	ip = "192.168.1.2\n",
}

local function equal(actual, expected, message)
	assert(
		actual == expected,
		(message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	)
end

local function kind(command)
	if command:find("-listallhardwareports", 1, true) then
		return "discovery"
	end
	if command:find("-getairportpower", 1, true) then
		return "power"
	end
	if command:find("getsummary", 1, true) then
		return "summary"
	end
	if command:find("getifaddr", 1, true) then
		return "ip"
	end
	if command:find("/sbin/ifconfig", 1, true) then
		return "link"
	end
	error("unexpected command: " .. command)
end

local function fixture(overrides)
	local env = { items = {}, calls = {}, pending = {}, responses = {}, now = 1000 }
	for key, value in pairs(defaults) do
		env.responses[key] = value
	end
	for key, value in pairs(overrides or {}) do
		env.responses[key] = value
	end

	local sbar = {}
	function sbar.add(_, name, config)
		local item = {
			name = name,
			config = config,
			handlers = {},
			updates = 0,
			icon = config.icon or {},
			label = config.label and config.label.string,
		}
		function item:set(values)
			self.updates = self.updates + 1
			if values.icon then
				for key, value in pairs(values.icon) do
					self.icon[key] = value
				end
			end
			if values.label then
				self.label = type(values.label) == "table" and values.label.string or values.label
			end
			if values.popup then
				self.open = values.popup.drawing
			end
		end
		function item:query()
			return { popup = { drawing = self.open and "on" or "off" } }
		end
		function item:subscribe(events, callback)
			if type(events) == "string" then
				events = { events }
			end
			for _, event in ipairs(events) do
				self.handlers[event] = callback
			end
		end
		env.items[name] = item
		return item
	end
	function sbar.exec(command, callback)
		local call = { kind = kind(command), command = command, callback = callback }
		env.calls[#env.calls + 1] = call
		env.pending[#env.pending + 1] = call
	end

	function env:take(expected)
		local call = table.remove(self.pending, 1)
		assert(call, "no command pending: " .. expected)
		equal(call.kind, expected, "command")
		return call.callback
	end
	function env:complete(expected)
		local seen = {}
		while #self.pending > 0 do
			assert(#seen < 20, "refresh loop")
			local call = table.remove(self.pending, 1)
			seen[#seen + 1] = call.kind
			call.callback(self.responses[call.kind])
		end
		equal(table.concat(seen, ","), expected, "command sequence/count")
	end
	function env:fire(event)
		self.items["widgets.wifi"].handlers[event]({ BUTTON = "left" })
	end
	function env:row(name)
		return self.items["widgets.wifi." .. name]
	end
	function env:icon(color, glyph)
		equal(self.items["widgets.wifi"].icon.color, color, "icon color")
		equal(self.items["widgets.wifi"].icon.string, glyph or icons.wifi.disconnected, "icon glyph")
	end

	os.time = function()
		return env.now
	end
	package.loaded.sketchybar = sbar
	package.loaded["lib.popup"] = nil
	package.loaded["items.widgets.wifi"] = nil
	require("items.widgets.wifi")
	return env
end

local function ready()
	local env = fixture()
	env:complete("discovery,link,ip")
	return env
end

local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

test("collapsed connected: two commands, cached interface, no popup row updates", function()
	local env = ready()
	equal(env.items["widgets.wifi"].config.update_freq, 30)
	env:icon(colors.white, icons.wifi.connected)
	for _, event in ipairs({ "routine", "forced", "system_woke", "wifi_change" }) do
		env:fire(event)
		env:complete("link,ip")
	end
	for _, row in ipairs({ "heading", "connection", "ssid", "ip", "router", "interface" }) do
		equal(env:row(row).updates, 0, row .. " hidden updates")
	end
end)

test("collapsed inactive or powered off: one command", function()
	local env = fixture({ link = "en0: flags=8863\n\tstatus: inactive\n", power = "Wi-Fi Power (en0): Off\n" })
	env:complete("discovery,link")
	env:icon(colors.grey)
	env:fire("routine")
	env:complete("link")
end)

test("collapsed active without valid IP preserves connecting icon", function()
	local env = fixture({ ip = "0.0.0.0\n" })
	env:complete("discovery,link,ip")
	env:icon(colors.orange)
end)

test("open popup: three commands, summary avoids ifconfig, all details rendered", function()
	local env = ready()
	env:fire("mouse.clicked")
	env:complete("power,summary,ip")
	equal(env:row("heading").label, "Test Wi-Fi")
	equal(env:row("connection").label, "Connected")
	equal(env:row("ssid").label, "Test Wi-Fi")
	equal(env:row("ip").label, "192.168.1.2")
	equal(env:row("router").label, "192.168.1.1")
	equal(env:row("interface").label, "en0")
	env:fire("routine")
	env:complete("power,summary,ip")
	equal(env:row("ip").updates, 2)
	env:fire("mouse.exited.global")
	env:fire("routine")
	env:complete("link,ip")
	equal(env:row("ip").updates, 2)
end)

test("powered off popup: power command alone and stale details cleared", function()
	local env = ready()
	env:fire("mouse.clicked")
	env:complete("power,summary,ip")
	env.responses.power = "Wi-Fi Power (en0): Off\n"
	env:fire("wifi_change")
	env:complete("power")
	env:icon(colors.grey)
	equal(env:row("connection").label, "Radio off")
	equal(env:row("heading").label, "Wi-Fi")
	for _, row in ipairs({ "ssid", "ip", "router" }) do
		equal(env:row(row).label, "—")
	end
end)

test("explicit inactive summary: two commands, no fallback or IP", function()
	local env = ready()
	env.responses.summary = "LinkStatusActive : FALSE\n  SSID : Stale\n  Router : 192.168.1.1\n"
	env:fire("mouse.clicked")
	env:complete("power,summary")
	env:icon(colors.grey)
	equal(env:row("connection").label, "Disconnected")
	equal(env:row("ssid").label, "—")
end)

test("missing summary link field uses fallback only when necessary", function()
	local env = ready()
	env.responses.summary = "Interface: en0\n  SSID : Fallback\n  Router : 192.168.1.1\n"
	env:fire("mouse.clicked")
	env:complete("power,summary,link,ip")
	env:icon(colors.white, icons.wifi.connected)
	equal(env:row("ssid").label, "Fallback")
	env.responses.link = "\tstatus: inactive\n"
	env:fire("routine")
	env:complete("power,summary,link")
	equal(env:row("connection").label, "Disconnected")
end)

test("empty summary still uses link/IP fallback and hides unavailable SSID", function()
	local env = ready()
	env.responses.summary = ""
	env:fire("mouse.clicked")
	env:complete("power,summary,link,ip")
	equal(env:row("ssid").label, "Hidden by macOS")
	equal(env:row("heading").label, "Wi-Fi")
end)

test("redacted SSID and missing IP preserve popup behavior", function()
	local env = ready()
	env.responses.summary = "\nLinkStatusActive : TRUE\nSSID : <redacted>\n"
	env:fire("mouse.clicked")
	env:complete("power,summary,ip")
	equal(env:row("ssid").label, "Hidden by macOS")
	env.responses.ip = ""
	env:fire("routine")
	env:complete("power,summary,ip")
	env:icon(colors.orange)
	equal(env:row("connection").label, "Connecting…")
end)

test("popup opened during routine link query is queued, not lost", function()
	local env = ready()
	env:fire("routine")
	env:fire("mouse.clicked")
	equal(#env.pending, 1)
	env:complete("link,ip,power,summary,ip")
	equal(env:row("connection").label, "Connected")
	equal(env:row("ssid").updates, 1)
end)

test("popup opened during routine IP query is queued, not lost", function()
	local env = ready()
	env:fire("routine")
	env:take("link")(env.responses.link)
	env:fire("mouse.clicked")
	env:complete("ip,power,summary,ip")
	equal(env:row("ssid").label, "Test Wi-Fi")
end)

test("popup opened during initial interface discovery is queued", function()
	local env = fixture()
	env:fire("mouse.clicked")
	env:complete("discovery,link,ip,power,summary,ip")
	equal(env:row("connection").label, "Connected")
end)

test("overlapping events coalesce into one additional refresh", function()
	local env = ready()
	env:fire("routine")
	env:fire("wifi_change")
	env:fire("forced")
	env:fire("system_woke")
	env:complete("link,ip,link,ip")
end)

test("closing a popup during refresh suppresses hidden row updates", function()
	local env = ready()
	env:fire("mouse.clicked")
	env:fire("mouse.exited.global")
	env:complete("power,summary,ip")
	equal(env:row("ssid").updates, 0)
	env:fire("routine")
	env:complete("link,ip")
end)

test("lost discovery callback recovers on next routine; stale discovery ignored", function()
	local env = fixture()
	local late = env:take("discovery")
	env.now = env.now + 64
	env:fire("routine")
	equal(#env.calls, 1)
	equal(#env.pending, 0)
	env.now = env.now + 1
	env:fire("routine")
	env:complete("discovery,link,ip")
	local count = #env.calls
	late("Hardware Port: Wi-Fi\nDevice: en9\n")
	equal(#env.calls, count)
	env:fire("routine")
	assert(env.calls[#env.calls].command:find("'en0'", 1, true))
	env:complete("link,ip")
end)

test("lost routine callback plus pending popup recovers as detailed refresh", function()
	local env = ready()
	env:fire("routine")
	local late = env:take("link")
	local before_recovery = #env.calls
	env.now = env.now + 64
	env:fire("mouse.clicked")
	equal(#env.calls, before_recovery)
	equal(#env.pending, 0)
	env.now = env.now + 1
	env:fire("routine")
	env:complete("power,summary,ip")
	local count = #env.calls
	late("status: inactive")
	equal(#env.calls, count)
	env:icon(colors.white, icons.wifi.connected)
	equal(env:row("connection").label, "Connected")
end)

test("stale IP completion cannot clear newer inflight request", function()
	local env = ready()
	env:fire("routine")
	env:take("link")(env.responses.link)
	local late = env:take("ip")
	local before_recovery = #env.calls
	env.now = env.now + 64
	env:fire("routine")
	equal(#env.calls, before_recovery)
	equal(#env.pending, 0)
	env.now = env.now + 1
	env:fire("routine")
	late("")
	env:icon(colors.white, icons.wifi.connected)
	env:fire("mouse.clicked")
	equal(#env.pending, 1)
	env:complete("link,ip,power,summary,ip")
	equal(env:row("connection").label, "Connected")
end)

test("chained command dispatch renews the per-command recovery deadline", function()
	local env = fixture()
	local start = env.now
	local discovery = env:take("discovery")
	env.now = start + 50
	discovery(env.responses.discovery)
	local late = env:take("link")
	equal(#env.calls, 2)

	-- Discovery's original deadline has passed, but the link command is only 15s old.
	env.now = start + 65
	env:fire("routine")
	equal(#env.calls, 2)
	equal(#env.pending, 0)
	env.now = start + 114
	env:fire("routine")
	equal(#env.calls, 2)
	equal(#env.pending, 0)

	env.now = start + 115
	env:fire("routine")
	equal(#env.calls, 3)
	env:complete("link,ip")
	local count = #env.calls
	late("status: inactive")
	equal(#env.calls, count)
	env:icon(colors.white, icons.wifi.connected)
end)

test("no Wi-Fi interface remains unavailable and retries discovery", function()
	local env = fixture({ discovery = "Hardware Port: Ethernet\nDevice: en1\n" })
	env:complete("discovery")
	env:icon(colors.grey)
	env:fire("mouse.clicked")
	env:complete("discovery")
	equal(env:row("connection").label, "Unavailable")
	equal(env:row("interface").label, "—")
end)

test("known tradeoff: stale active link and IP can look connected with radio off", function()
	local env = fixture({ power = "Wi-Fi Power (en0): Off\n" })
	-- Collapsed polls have no power evidence: stale link/IP can produce a false positive.
	env:complete("discovery,link,ip")
	env:icon(colors.white, icons.wifi.connected)
	env:fire("mouse.clicked")
	env:complete("power")
	env:icon(colors.grey)
	equal(env:row("connection").label, "Radio off")
	-- Opening the popup verifies power, but subsequent collapsed polls still trust link/IP.
	env:fire("mouse.exited.global")
	env:fire("routine")
	env:complete("link,ip")
	env:icon(colors.white, icons.wifi.connected)
end)

os.time = real_time
os.execute = real_execute
io.popen = real_popen
package.preload.sketchybar = real_sketchybar_loader
print("PASS: " .. total .. " Wi-Fi regression tests")
