-- Pure network parsing and command construction tests; no commands are executed.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. package.path
local controls = require("lib.network_controls")
local utils = require("lib.utils")
local total = 0

local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end

local counters = [[
Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
en0 1500 <Link#12> aa:bb:cc:dd:ee:ff 10 0 12345678 12 0 345678 0
en0 1500 192.168.1 192.168.1.2 10 - 99999999 12 - 99999999 -
utun0 1380 <Link#15> 20 0 100000 10 0 200000 0
en8* 1500 <Link#10> aa:bb:cc:dd:ee:00 0 0 0 0 0 0 0
]]

test("link counters do not double count duplicate IP rows", function()
	local sample = assert(controls.counters(counters, "en0"))
	equal(sample.interface, "en0")
	equal(sample.rx_bytes, 12345678)
	equal(sample.tx_bytes, 345678)
end)

test("header offsets support addressless link rows and disabled interfaces", function()
	local sample = assert(controls.counters(counters, "utun0"))
	equal(sample.rx_bytes, 100000)
	equal(sample.tx_bytes, 200000)
	equal(assert(controls.counters(counters, "en8")).rx_bytes, 0)
	equal(controls.counters(counters, "en9"), nil)
end)

test("header names drive counter positions rather than fixed numeric indices", function()
	local raw = [[
Name Mtu Network Address Ibytes Obytes Ipkts Ierrs Opkts Oerrs Coll
en0 1500 <Link#1> aa:bb:cc:dd:ee:ff 999 555 1 0 2 0 0
]]
	local sample = assert(controls.counters(raw, "en0"))
	equal(sample.rx_bytes, 999)
	equal(sample.tx_bytes, 555)
end)

test("missing headers, failed reads and malformed counters are unavailable", function()
	equal(controls.counters("netstat: Operation not permitted", "en0"), nil)
	equal(controls.counters(nil, "en0"), nil)
	equal(controls.counters(counters:gsub("12345678", "bad"), "en0"), nil)
	equal(controls.counters(counters:gsub("12345678", "-1"), "en0"), nil)
	equal(controls.counters(counters:gsub("12345678", "1e999"), "en0"), nil)
end)

local prior = { interface = "en0", rx_bytes = 1000, tx_bytes = 500 }
local current = { interface = "en0", rx_bytes = 5000, tx_bytes = 2500 }

test("rates use byte deltas divided by the actual sample interval", function()
	local rates = assert(controls.rates(current, prior, 12, 10))
	equal(rates.download, 2000)
	equal(rates.upload, 1000)
	local idle = assert(controls.rates(prior, prior, 11, 10))
	equal(idle.download, 0)
	equal(idle.upload, 0)
end)

test("first samples, interface changes and counter resets cannot create spikes", function()
	equal(controls.rates(current, nil, 12, 10), nil)
	equal(controls.rates({ interface = "en1", rx_bytes = 5000, tx_bytes = 2500 }, prior, 12, 10), nil)
	equal(controls.rates(prior, current, 12, 10), nil)
	equal(controls.rates({ interface = "en0", rx_bytes = 5000, tx_bytes = 0 }, prior, 12, 10), nil)
	equal(controls.rates({ interface = "en0", rx_bytes = math.huge, tx_bytes = 500 }, prior, 12, 10), nil)
end)

test("wake gaps and invalid timestamps reset throughput sampling", function()
	for _, now in ipairs({ 10, 9, 41, math.huge, 0 / 0 }) do
		equal(controls.rates(current, prior, now, 10), nil)
	end
	equal(controls.rates(current, prior, 12, nil), nil)
	assert(controls.rates(current, prior, 40, 10))
end)

test("rate labels use explicit binary byte units", function()
	equal(controls.format_bytes(0), "0 B")
	equal(controls.format_bytes(1536), "1.5 KiB")
	equal(controls.format_bytes(1024 ^ 2), "1.0 MiB")
	equal(controls.format_rate(1536), "1.5 KiB/s")
	equal(controls.format_rate(-1), "--")
	equal(controls.format_rate(nil), "--")
	equal(controls.format_rate(0 / 0), "--")
end)

local services = [[
An asterisk (*) denotes that a network service is disabled.
(1) Wired service
(Hardware Port: USB LAN, Device: en8)
(*) Disabled Wireless
(Hardware Port: Wi-Fi, Device: en1)
(3) Work's Wireless $(test)
(Hardware Port: Wi-Fi, Device: en0)
(4) *Disabled elsewhere
(Hardware Port: Wi-Fi, Device: en2)
]]

test("actual service selection supports renamed and shell-sensitive service names", function()
	equal(controls.service(services, "en0"), "Work's Wireless $(test)")
	equal(controls.service(services, "en8"), "Wired service")
	equal(controls.service(services, "en9"), nil)
end)

test("disabled services and missing service reports never select a target", function()
	equal(controls.service(services, "en1"), nil)
	equal(controls.service(services, "en2"), nil)
	equal(controls.service(nil, "en0"), nil)
	equal(controls.service("Device: en0", "en0"), nil)
end)

test("automatic DNS requires explicit successful no-server output", function()
	equal(controls.dns("There aren't any DNS Servers set on Work Wireless.\n", 0).provider, "automatic")
	for _, raw in ipairs({ "", "You are not authorized", "networksetup: bad service", "Empty" }) do
		equal(controls.dns(raw, 0).provider, "unavailable")
	end
	equal(controls.dns("There aren't any DNS Servers set on Wi-Fi.\n", 1).provider, "unavailable")
	equal(controls.dns("1.1.1.1", nil).provider, "unavailable")
end)

test("provider matching accepts IPv4-only subsets and expanded IPv6 spelling", function()
	equal(controls.dns("1.1.1.1\n1.0.0.1\n", 0).provider, "cloudflare")
	equal(controls.dns("2001:4860:4860:0:0:0:0:8888\n", 0).provider, "google")
	equal(controls.dns("2620:FE:0:0:0:0:0:FE\n", 0).provider, "quad9")
	equal(controls.dns("8.8.4.4", 0).provider, "google")
end)

test("mixed and custom DNS servers preserve their exact ordered address list", function()
	local dns = controls.dns("1.1.1.1\n8.8.8.8\nfe80::1%en0\n", 0)
	equal(dns.provider, "custom")
	equal(table.concat(dns.addresses, ","), "1.1.1.1,8.8.8.8,fe80::1%en0")
	equal(controls.dns("192.168.1.1\n192.168.1.1\n", 0).addresses[2], nil)
end)

test("custom DNS validation accepts IPv4 and IPv6 but rejects malformed addresses", function()
	for _, address in ipairs({
		"127.0.0.1",
		"::1",
		"::",
		"1::",
		"1:2::",
		"::ffff:192.0.2.1",
		"fe80::1%en0",
		"2001:db8::1",
	}) do
		equal(controls.valid_address(address), true)
	end
	for _, address in ipairs({
		"256.0.0.1",
		"01.1.1.1",
		"1.1.1",
		"1.1.1.1; touch /tmp/unwanted",
		"$(say surprise)",
		"fe80:::1",
		"fe80::1::2",
		":1::2",
		"1::2:",
		":1::",
		"::1:",
		"fe80:1",
		"1:2:3:4:5:6:7:8:9",
		"1:2:3:4:5:6:7:8::",
		"12345::1",
		"::ffff:999.0.0.1",
		"fe80::1%",
	}) do
		equal(controls.valid_address(address), false)
	end
end)

test("DNS address input supports commas, deduplicates and bounds list size", function()
	local addresses = assert(controls.parse_addresses("1.1.1.1, 1.0.0.1\n1.1.1.1"))
	equal(table.concat(addresses, ","), "1.1.1.1,1.0.0.1")
	equal(controls.parse_addresses(""), nil)
	equal(controls.parse_addresses("1.1.1.1,invalid"), nil)
	equal(controls.validate_addresses({ "1.1.1.1", false }), nil)
	equal(controls.validate_addresses({ "1.1.1.1 8.8.8.8" }), nil)
	equal(controls.validate_addresses({ name = "1.1.1.1" }), nil)
	local too_many = {}
	for value = 1, 9 do
		too_many[value] = "192.168.1." .. value
	end
	equal(controls.validate_addresses(too_many), nil)
end)

test("DNS readback comparison checks complete canonical sets and automatic empties", function()
	equal(controls.same_dns({}, {}), true)
	equal(controls.same_dns({ provider = "automatic", addresses = {} }, {}), true)
	equal(controls.same_dns({ "1.1.1.1", "1.0.0.1" }, { "1.0.0.1", "1.1.1.1" }), true)
	equal(controls.same_dns({ "2001:4860:4860::8888" }, { "2001:4860:4860:0:0:0:0:8888" }), true)
	equal(controls.same_dns(controls.dns("1.1.1.1\n", 0), controls.providers[2].addresses), false)
	equal(controls.same_dns({ "1.1.1.1" }, { "8.8.8.8" }), false)
	equal(controls.same_dns({ provider = "unavailable", addresses = {} }, {}), false)
	equal(controls.same_dns(nil, {}), false)
	equal(controls.same_dns({ "bad" }, {}), false)
end)

test("named DNS commands include IPv4 and IPv6 addresses and quote the service", function()
	local service = "Work's Wireless $(touch /tmp/unwanted) `device`"
	local command = assert(controls.dns_command(service, "cloudflare"))
	equal(
		command,
		"/usr/sbin/networksetup -setdnsservers "
			.. utils.quote(service)
			.. " '1.1.1.1' '1.0.0.1' '2606:4700:4700::1111' '2606:4700:4700::1001'"
	)
	equal(controls.dns_command("Wi-Fi", "automatic"), "/usr/sbin/networksetup -setdnsservers 'Wi-Fi' Empty")
end)

test("custom DNS commands validate all addresses and reject unknown targets", function()
	equal(
		controls.dns_command("Wi-Fi", "custom", { "192.168.1.1", "::1" }),
		"/usr/sbin/networksetup -setdnsservers 'Wi-Fi' '192.168.1.1' '::1'"
	)
	equal(controls.dns_command("Wi-Fi", "custom", { "1.1.1.1", "$(touch /tmp/unwanted)" }), nil)
	equal(controls.dns_command("Wi-Fi", "unknown"), nil)
	equal(controls.dns_command(nil, "cloudflare"), nil)
	equal(controls.dns_command("Work\nWireless", "google"), nil)
end)

test("radio command requires a real interface token and boolean target", function()
	equal(controls.power_command("en0", true), "/usr/sbin/networksetup -setairportpower 'en0' on")
	equal(controls.power_command("en0", false), "/usr/sbin/networksetup -setairportpower 'en0' off")
	equal(controls.power_command("en0; reboot", false), nil)
	equal(controls.power_command("$(reboot)", true), nil)
	equal(controls.power_command("en0", "off"), nil)
	equal(controls.power_command(nil, true), nil)
end)

test("ping parser reads average latency and packet loss", function()
	local result = assert(controls.ping(
		[[
64 bytes from 1.1.1.1: icmp_seq=0 ttl=57 time=12.513 ms
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 11.981/12.365/12.604/0.274 ms
]],
		0
	))
	equal(result.latency, 12.365)
	equal(result.loss, 0)
end)

test("ping loss is separate from unreachable or malformed output", function()
	local lost = assert(controls.ping("3 packets transmitted, 0 packets received, 100.0% packet loss", 2))
	equal(lost.latency, nil)
	equal(lost.loss, 100)
	equal(controls.ping("ping: Operation not permitted", 2), nil)
	equal(controls.ping("invalid", 0), nil)
	equal(controls.ping("3 packets transmitted, 0 received, 500% packet loss", 2), nil)
end)

print("PASS: " .. total .. " network control tests")
