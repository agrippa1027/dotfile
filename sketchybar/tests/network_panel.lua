-- Run with lua sketchybar/tests/network_panel.lua. No hardware commands run.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local root = script_dir .. ".."
package.path = root .. "/?.lua;" .. package.path
local controls = require("lib.network_controls")
local colors = require("colors")
local settings = require("settings")
local utils = require("lib.utils")

local service_order = [[An asterisk (*) denotes that a network service is disabled.
(1) USB Ethernet
(Hardware Port: USB Ethernet, Device: en8)
(2) Office Wi-Fi
(Hardware Port: Wi-Fi, Device: en0)
]]
local automatic = "There aren't any DNS Servers set on Office Wi-Fi.\n"
local function provider_raw(id)
	for _, provider in ipairs(controls.providers) do
		if provider.id == id then
			return #provider.addresses == 0 and automatic or table.concat(provider.addresses, "\n") .. "\n"
		end
	end
	error("Unknown fixture provider: " .. id)
end

local function counters(rx, tx)
	return string.format(
		"Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll\n"
			.. "en0 1500 <Link#12> aa:bb:cc:dd:ee:ff 20 0 %d 10 0 %d 0\n"
			.. "en0 1500 192.168.1 192.168.1.2 20 - %d 10 - %d -\n",
		rx,
		tx,
		rx,
		tx
	)
end

local function equal(actual, expected, context)
	assert(
		actual == expected,
		(context or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
	)
end

local function contains(actual, expected)
	assert(
		type(actual) == "string" and actual:find(expected, 1, true),
		"expected '" .. tostring(actual) .. "' to contain '" .. expected .. "'"
	)
end

local function merge(target, values)
	for key, value in pairs(values) do
		if type(value) == "table" then
			target[key] = type(target[key]) == "table" and target[key] or {}
			merge(target[key], value)
		elseif (key == "label" or key == "icon") and type(value) == "string" then
			target[key] = type(target[key]) == "table" and target[key] or {}
			target[key].string = value
		else
			target[key] = value
		end
	end
end

local function fixture(options)
	options = options or {}
	local env = { items = {}, calls = {}, pending = {}, now = 1000, refreshes = 0 }
	local sbar = {}
	function sbar.add(kind, name, third, fourth)
		local item = { name = name, properties = fourth or third or {}, handlers = {}, pushes = {}, kind = kind }
		function item:set(values)
			merge(self.properties, values)
		end
		function item:query()
			return { popup = { drawing = "on" } }
		end
		function item:subscribe(events, handler)
			for _, event in ipairs(type(events) == "table" and events or { events }) do
				self.handlers[event] = handler
			end
		end
		function item:push(values)
			for _, value in ipairs(values) do
				self.pushes[#self.pushes + 1] = value
			end
		end
		env.items[name] = item
		return item
	end
	function sbar.exec(command, callback)
		local call = { command = command, callback = callback }
		env.calls[#env.calls + 1] = call
		if callback then
			env.pending[#env.pending + 1] = call
		end
	end
	function env:item(suffix)
		return assert(self.items["widgets.wifi." .. suffix], "missing item " .. suffix)
	end
	function env:label(suffix)
		return self:item(suffix).properties.label.string
	end
	function env:click(suffix)
		self:item(suffix).handlers["mouse.clicked"]({ BUTTON = "left" })
	end
	function env:tick(seconds)
		self.now = self.now + (seconds or 2)
		self:item("telemetry").handlers.routine({})
	end
	function env:count(pattern)
		local count = 0
		for _, call in ipairs(self.calls) do
			if call.command:find(pattern, 1, true) then
				count = count + 1
			end
		end
		return count
	end
	function env:take(pattern)
		for index, call in ipairs(self.pending) do
			if call.command:find(pattern, 1, true) then
				table.remove(self.pending, index)
				return call.callback, call.command
			end
		end
		error("Missing pending command: " .. pattern)
	end
	function env:reply(pattern, result, code)
		local callback = self:take(pattern)
		callback(result, code == nil and 0 or code)
	end
	function env:dns_reply(raw, code)
		self:reply("-listnetworkserviceorder", service_order)
		self:reply("-getdnsservers", raw or provider_raw("cloudflare"), code)
	end
	function env:open()
		self.panel:open()
		self:dns_reply()
	end
	local modules = {
		sketchybar = sbar,
		colors = colors,
		settings = settings,
		["lib.utils"] = utils,
		["lib.network_controls"] = controls,
	}
	local isolated = setmetatable({
		require = function(name)
			return assert(modules[name], "Unexpected require: " .. name)
		end,
		os = {
			time = function()
				return env.now
			end,
			date = function()
				return "12:34"
			end,
			getenv = function()
				return options.config_dir
			end,
			rename = function()
				error("Real filesystem changes disabled")
			end,
		},
		io = {
			open = function()
				if options.config_dir then
					return nil, "Mock filesystem is read-only"
				end
				error("Real filesystem access disabled")
			end,
		},
	}, { __index = _G })
	local module = assert(loadfile(root .. "/items/widgets/network_panel.lua", "t", isolated))()
	env.owner = sbar.add("item", "widgets.wifi", {})
	env.device = "en0"
	env.connection = { state = "connected", router = "192.168.1.1" }
	env.detail = sbar.add("item", "connection.detail", { drawing = false })
	env.panel = module.attach(env.owner, {
		get_interface = function()
			return env.device
		end,
		get_status = function()
			return env.connection
		end,
		refresh = function()
			env.refreshes = env.refreshes + 1
		end,
		detail_items = { env.detail },
	})
	return env
end

local total, failures = 0, {}
local function test(name, run)
	total = total + 1
	local ok, reason = pcall(run)
	if ok then
		print("ok " .. total .. " - " .. name)
	else
		failures[#failures + 1] = name .. ": " .. tostring(reason)
		print("not ok " .. total .. " - " .. failures[#failures])
	end
end

test("opening starts telemetry; closing stops reads without changing settings", function()
	local env = fixture()
	equal(#env.calls, 0)
	equal(env.owner.properties.popup.columns, 2)
	equal(env:item("telemetry").properties.update_freq, 0)
	env:open()
	equal(env:item("telemetry").properties.update_freq, 2)
	equal(env:count("-setdnsservers"), 0)
	equal(env:count("-setairportpower"), 0)
	equal(env:count("networkQuality"), 0)
	env.panel:close()
	equal(env:item("telemetry").properties.update_freq, 0)
	local count = #env.calls
	env:tick()
	equal(#env.calls, count)
end)

test("counter deltas become transfer rates without summing duplicate IP rows", function()
	local env = fixture()
	env:open()
	env:reply("netstat", counters(1000, 500))
	contains(env:label("download"), "Sampling")
	env:tick(2)
	env:reply("netstat", counters(3048, 2548))
	contains(env:label("download"), "1.0 KiB/s")
	contains(env:label("upload"), "1.0 KiB/s")
	contains(env:label("received"), "3.0 KiB")
	local pushed = env:item("download.history").pushes
	equal(pushed[#pushed], 1024 / (10 * 1024 * 1024))
end)

test("closed or superseded counter samples cannot replace current readings", function()
	local env = fixture()
	env:open()
	local stale = env:take("netstat")
	env.panel:close()
	env.panel:open()
	env:dns_reply()
	env:reply("netstat", counters(9000, 8000))
	local received = env:label("received")
	stale(counters(999999, 999999), 0)
	equal(env:label("received"), received)
end)

test("pending telemetry reads coalesce and an expired read cannot replace its retry", function()
	local env = fixture()
	env:open()
	local stale = env:take("netstat")
	env:tick(2)
	equal(env:count("netstat"), 1)
	env:tick(6)
	equal(env:count("netstat"), 2)
	env:reply("netstat", counters(12000, 8000))
	local received = env:label("received")
	stale(counters(999999, 999999), 0)
	equal(env:label("received"), received)
end)

test("known DNS providers render their actual name and selected choice", function()
	local env = fixture()
	env:open()
	contains(env:label("dns.heading"), "Cloudflare")
	equal(env:item("dns.cloudflare").properties.label.color, colors.accent)
	contains(env:label("dns.cloudflare"), "●")
end)

test("DNS changes reread service state, serialize clicks, and verify the new provider", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	equal(env:count("-setdnsservers"), 0)
	local calls = #env.calls
	env:click("dns.quad9")
	equal(#env.calls, calls)
	env:dns_reply()
	equal(env:count("-setdnsservers"), 1)
	local done, command = env:take("-setdnsservers")
	contains(command, "'Office Wi-Fi'")
	contains(command, "'8.8.8.8'")
	done("", 0)
	env:dns_reply(provider_raw("google"))
	equal(env:item("dns.google").properties.label.color, colors.accent)
	contains(env:label("action.status"), "DNS updated")
end)

test("a failed DNS read prevents writes and leaves a useful error", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	env:dns_reply("not authorized", 1)
	equal(env:count("-setdnsservers"), 0)
	contains(env:label("action.status"), "Cannot read DNS")
	equal(env:item("action.status").properties.label.color, colors.red)
end)

test("closing a panel cancels a pending DNS preflight and permits a fresh action", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	local stale = env:take("-listnetworkserviceorder")
	env.panel:close()
	stale(service_order, 0)
	equal(env:count("-setdnsservers"), 0)
	env.panel:open()
	env:dns_reply()
	env:click("dns.google")
	env:dns_reply()
	equal(env:count("-setdnsservers"), 1)
end)

test("reopening during DNS readback releases the superseded action", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	env:dns_reply()
	local write_done = env:take("-setdnsservers")
	env.panel:close()
	write_done("", 0)
	local stale_readback = env:take("-listnetworkserviceorder")
	env.panel:open()
	env:dns_reply(provider_raw("google"))
	stale_readback(service_order, 0)
	local queries = env:count("-listnetworkserviceorder")
	env:click("dns.quad9")
	equal(env:count("-listnetworkserviceorder"), queries + 1, "fresh action starts without waiting for watchdog")
	env:dns_reply(provider_raw("google"))
	equal(env:count("-setdnsservers"), 2)
	env:reply("-setdnsservers", "")
	env:dns_reply(provider_raw("quad9"))
	equal(env:item("dns.quad9").properties.label.color, colors.accent)
end)

test("service changes during preflight require choosing DNS again", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	env:reply("-listnetworkserviceorder", (service_order:gsub("Office Wi%-Fi", "New Wi-Fi")))
	env:reply("-getdnsservers", provider_raw("cloudflare"))
	equal(env:count("-setdnsservers"), 0)
	contains(env:label("action.status"), "service changed")
end)

test("a previous DNS snapshot must be saved before every first mutation attempt", function()
	local env = fixture({ config_dir = "/mock/read-only-config" })
	env:open()
	for _ = 1, 2 do
		env:click("dns.google")
		env:dns_reply()
		equal(env:count("-setdnsservers"), 0)
		contains(env:label("action.status"), "Could not save previous DNS")
	end
end)

test("DNS readback mismatch is not reported as success", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	env:dns_reply()
	env:reply("-setdnsservers", "")
	env:dns_reply(provider_raw("cloudflare"))
	equal(env:item("action.status").properties.label.color, colors.red)
	assert(not env:label("action.status"):find("DNS updated", 1, true))
end)

test("custom DNS rejects shell text without issuing a network write", function()
	local env = fixture()
	env:open()
	env:click("dns.custom")
	env:reply("display dialog", "1.1.1.1; touch /tmp/not-allowed")
	env:dns_reply()
	equal(env:count("-setdnsservers"), 0)
	contains(env:label("action.status"), "Invalid DNS")
end)

test("cancelling a custom DNS dialog leaves configuration untouched", function()
	local env = fixture()
	env:open()
	env:click("dns.custom")
	local calls = #env.calls
	env:click("dns.custom")
	equal(#env.calls, calls, "only one dialog at a time")
	env:reply("display dialog", "User canceled", 1)
	equal(env:count("-setdnsservers"), 0)
end)

test("restoring previous DNS uses the exact original address set", function()
	local env = fixture()
	env:open()
	env:click("dns.google")
	env:dns_reply()
	env:reply("-setdnsservers", "")
	env:dns_reply(provider_raw("google"))
	env:click("dns.restore")
	env:dns_reply(provider_raw("google"))
	local done, command = env:take("-setdnsservers")
	for _, provider in ipairs(controls.providers) do
		if provider.id == "cloudflare" then
			for _, address in ipairs(provider.addresses) do
				contains(command, utils.quote(address))
			end
		end
	end
	done("", 0)
	env:dns_reply(provider_raw("cloudflare"))
	equal(env:item("dns.cloudflare").properties.label.color, colors.accent)
end)

test("Wi-Fi power only changes after its action is clicked", function()
	local env = fixture()
	env:open()
	equal(env:count("-setairportpower"), 0)
	env:click("power")
	local done, command = env:take("-setairportpower")
	contains(command, "'en0' off")
	done("", 0)
	equal(env.refreshes, 1)
	env.connection.state = "off"
	env.panel:status(env.connection)
	contains(env:label("power"), "Turn Wi-Fi on")
	env:click("power")
	local _, on = env:take("-setairportpower")
	contains(on, "'en0' on")
end)

test("speed test is opt-in and presents measured JSON results in Mbps", function()
	local env = fixture()
	env:open()
	equal(env:count("networkQuality"), 0)
	env:click("speedtest")
	local done, command = env:take("networkQuality")
	contains(command, "-M 20")
	contains(command, "-I 'en0'")
	done({ dl_throughput = 125000000, ul_throughput = 17500000 }, 0)
	equal(env:item("speedtest.download").properties.drawing, true)
	contains(env:label("speedtest.download"), "125.0 Mbps")
	contains(env:label("speedtest.upload"), "17.5 Mbps")
	contains(env:label("action.status"), "complete")
end)

test("failed speed tests do not display old or invented measurements", function()
	local env = fixture()
	env:open()
	env:click("speedtest")
	env:reply("networkQuality", "test unavailable", 1)
	equal(env:item("speedtest.download").properties.drawing, false)
	equal(env:item("speedtest.upload").properties.drawing, false)
	equal(env:item("action.status").properties.label.color, colors.red)
end)

test("speed test rejects non-finite measured values", function()
	for _, result in ipairs({
		{ dl_throughput = math.huge, ul_throughput = 100 },
		{ dl_throughput = 100, ul_throughput = 0 / 0 },
	}) do
		local env = fixture()
		env:open()
		env:click("speedtest")
		env:reply("networkQuality", result)
		equal(env:item("speedtest.download").properties.drawing, false)
		equal(env:item("speedtest.upload").properties.drawing, false)
		equal(env:item("action.status").properties.label.color, colors.red)
	end
end)

test("connection details expand and collapse as a group", function()
	local env = fixture()
	env:click("details")
	equal(env.detail.properties.drawing, true)
	env:click("details")
	equal(env.detail.properties.drawing, false)
end)

if #failures > 0 then
	error(string.format("FAIL: %d of %d network-panel tests\n%s", #failures, total, table.concat(failures, "\n")), 0)
end
print("PASS: " .. total .. " network-panel regression tests")
