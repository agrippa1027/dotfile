local network = require("lib.network")
local utils = require("lib.utils")

local function equal(actual, expected, label)
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

equal(
	network.interface("Hardware Port: Ethernet\nDevice: en3\nHardware Port: Wi-Fi\nDevice: en0\n"),
	"en0",
	"Wi-Fi interface discovery"
)
equal(network.interface("Hardware Port: Ethernet\nDevice: en3\n"), nil, "No Wi-Fi interface")
equal(utils.quote("en0'"), "'en0'\\'''", "Shell quoting")

local summary = "\n  LinkStatusActive : TRUE\n  SSID : <redacted>\n  Router : 192.168.1.1\n"
local connected =
	network.parse({ interface = "en0", power = "Wi-Fi Power (en0): On\n", summary = summary, ip = "192.168.1.2\n" })
equal(connected.state, "connected", "Redacted SSID remains connected")
equal(connected.ssid, nil, "Redacted SSID omitted")
equal(connected.ip, "192.168.1.2", "IP is trimmed")
equal(connected.router, "192.168.1.1", "Router extraction")

local off =
	network.parse({ interface = "en0", power = "Wi-Fi Power (en0): Off\n", summary = summary, ip = "192.168.1.2" })
equal(off.state, "off", "Radio off overrides stale IP")
equal(off.ip, nil, "Radio off discards stale IP")
equal(network.parse({ interface = "en0", summary = summary }).state, "connecting", "Active link without IP")
equal(
	network.parse({
		interface = "en0",
		summary = "\nLinkStatusActive : FALSE\n",
		ip = "192.168.1.2",
		link = "status: active",
	}).state,
	"disconnected",
	"Explicit inactive link overrides ifconfig and stale IP"
)
equal(network.parse({ interface = "en0", link = "status: inactive" }).state, "disconnected", "Disconnected link")
equal(
	network.parse({ interface = "en0", link = "status: active", ip = "192.168.1.2" }).state,
	"connected",
	"Ifconfig fallback without SSID"
)
equal(network.parse({}).state, "unavailable", "Missing Wi-Fi device")

print("Network parser: 14 assertions passed")
