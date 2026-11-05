-- Pure Bluetooth parsing/command tests; no hardware commands are executed.
local script_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = script_dir .. "../?.lua;" .. package.path
local bt = require("lib.bluetooth_controls")
local total = 0
local function equal(actual, expected)
	assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
	run()
	total = total + 1
	print("ok " .. total .. " - " .. name)
end
local a, b, c = "aa:bb:cc:dd:ee:01", "aa:bb:cc:dd:ee:02", "aa:bb:cc:dd:ee:03"
local function device(address, name, connected, paired)
	return { address = address, name = name, connected = connected, paired = paired }
end

test("MAC addresses have one canonical identity", function()
	for _, input in ipairs({ "AA:BB:CC:DD:EE:01", "aa-bb-cc-dd-ee-01", "aabbccddee01" }) do
		equal(bt.address(input), a)
	end
end)

test("names, mixed separators and shell text cannot identify action targets", function()
	for _, input in ipairs({
		"Keyboard",
		" aa:bb:cc:dd:ee:01",
		"aa:bb:cc:dd:ee:01 ",
		"aa:bb-cc:dd:ee:01",
		"aa:bb:cc:dd:ee:01; open x",
		"$(id)",
		"aa:bb:cc:dd:ee",
		"aa:bb:cc:dd:ee:010",
		"gg:bb:cc:dd:ee:01",
	}) do
		equal(bt.address(input), nil)
		for _, action in ipairs({ "info", "connect", "disconnect", "pair", "unpair" }) do
			equal(bt.command(action, input), nil)
		end
	end
	equal(bt.address(false), nil)
	equal(bt.command("connect", {}), nil)
end)

test("commands are fixed and mutations require explicit validated targets", function()
	local reported = "/usr/bin/env BLUEUTIL_USE_SYSTEM_PROFILER=1 " .. bt.binary
	equal(bt.command("power"), bt.binary .. " --power")
	equal(bt.command("power", true), bt.binary .. " --power 1")
	equal(bt.command("power", false), bt.binary .. " --power 0")
	equal(bt.command("power", "toggle"), nil)
	equal(bt.command("paired"), reported .. " --paired --format json")
	equal(bt.command("connected"), reported .. " --connected --format json")
	equal(bt.command("inquiry"), bt.binary .. " --inquiry 8 --format json")
	equal(bt.command("inquiry", "8; id"), nil)
	equal(bt.command("paired", a), nil)
	for _, action in ipairs({ "connect", "disconnect", "pair", "unpair" }) do
		equal(bt.command(action, "AA-BB-CC-DD-EE-01"), bt.binary .. " --" .. action .. " '" .. a .. "'")
	end
	equal(bt.command("info", a), bt.binary .. " --info '" .. a .. "' --format json")
	equal(bt.command("connect; id", a), nil)
end)

test("multipoint connection checks use the current address-matched macOS snapshot", function()
	local stale_api = { device(a, "Headphones", false, true) }
	local macos = { device("AA-BB-CC-DD-EE-01", "Headphones", true, true) }
	equal(assert(bt.devices(stale_api, 0))[1].connected, false)
	equal(assert(bt.find_device(macos, 0, a)).connected, true)
	equal(assert(bt.find_device(stale_api, 0, a)).connected, false)
	equal(bt.find_device(macos, 1, a), nil)
	equal(bt.find_device(macos, 0, b), nil)
	equal(bt.find_device(macos, 0, "Headphones"), nil)
	equal(bt.find_device({}, 0, a), nil)
	equal(bt.find_device("unavailable", 0, a), nil)
end)

test("power failure and malformed output remain unknown", function()
	equal(bt.power(" 1\n", 0), true)
	equal(bt.power("0", 0), false)
	for _, raw in ipairs({ "on", "off", "true", "1 0", "", "10" }) do
		equal(bt.power(raw, 0), nil)
	end
	equal(bt.power("0", 1), nil)
	equal(bt.power(nil, 0), nil)
end)

test("list and single info responses use validated boolean flags and display fallbacks", function()
	local list = assert(
		bt.devices({ device(a, "  Keyboard\n Pro  ", 1, true), device(b, "", false, 0), device(c, nil, nil, nil) }, 0)
	)
	equal(#list, 3)
	local single = assert(bt.device(device(a, "  Keyboard\n Pro  ", 1, true), 0))
	equal(single.name, "Keyboard Pro")
	equal(single.connected, true)
	equal(single.paired, true)
	equal(assert(bt.device(device(b, "", false, 0), 0)).name, b)
	equal(bt.device(device(a, "x", "false", true), 0), nil)
	equal(bt.device(device(a, "x", true, "yes"), 0), nil)
	equal(bt.device(device(a, "x", true, true), 1), nil)
end)

test("a successful empty list differs from unavailable or malformed data", function()
	equal(#assert(bt.devices({}, 0)), 0)
	equal(bt.devices({}, 1), nil)
	equal(bt.devices("[]", 0), nil)
	equal(bt.devices(device(a, "x", false, true), 0), nil)
	equal(bt.devices({ [2] = device(a, "x", false, true) }, 0), nil)
	equal(bt.devices({ device("unsafe", "x", false, true) }, 0), nil)
	local list = assert(bt.devices({ device("unsafe", "x", false, true), device(a, "ok", false, true) }, 0))
	equal(#list, 1)
end)

test("duplicate paired rows merge by address and lists sort stably by name", function()
	local list = assert(bt.devices({
		device(b, "Zebra", false, true),
		device(a, "", false, false),
		device("AA-BB-CC-DD-EE-01", "Alpha", true, true),
		device(c, "Alpha", false, true),
	}, 0))
	equal(#list, 3)
	equal(list[1].address, a)
	equal(list[1].name, "Alpha")
	equal(list[1].connected, true)
	equal(list[1].paired, true)
	equal(list[2].address, c)
	equal(list[3].name, "Zebra")
	local missing = assert(bt.devices({ device(a, "Keyboard", false, false), device(a, "Keyboard") }, 0))
	equal(missing[1].connected, false)
	equal(missing[1].paired, false)
end)

local function report(state, connected, known)
	return {
		SPBluetoothDataType = {
			{
				controller_properties = { controller_state = state },
				device_connected = connected or {},
				device_not_connected = known or {},
			},
		},
	}
end

test("profiler failures and explicit radio off cannot expose stale connected rows", function()
	local stale = { { Headphones = { device_address = a } } }
	for _, result in ipairs({
		bt.profiler(nil, 0),
		bt.profiler(report("unknown", stale), 0),
		bt.profiler(report("attrib_on", stale), 1),
	}) do
		equal(result.powered, nil)
		equal(#result.devices, 0)
	end
	local off = bt.profiler(report("attrib_off", stale), 0)
	equal(off.powered, false)
	equal(#off.devices, 0)
end)

test("profiler fallback keeps redacted names read-only and actual connection groups", function()
	local native = bt.profiler(
		report(
			"attrib_on",
			{ { Keyboard = {} }, { Mouse = { device_address = a } } },
			{ { Headphones = { device_address = b } } }
		),
		0
	)
	equal(native.powered, true)
	equal(#native.devices, 3)
	equal(native.devices[1].name, "Headphones")
	equal(native.devices[1].connected, false)
	equal(native.devices[1].paired, true)
	equal(native.devices[2].name, "Keyboard")
	equal(native.devices[2].address, nil)
	equal(native.devices[2].connected, true)
	equal(bt.command("connect", native.devices[2].address), nil)
end)

test("battery labels expose only finite reported percentages", function()
	local native = bt.profiler(
		report("attrib_on", {
			{ Main = { device_address = a, device_batteryLevelMain = "75%" } },
			{
				Parts = {
					device_address = b,
					device_batteryLevelLeft = "80%",
					device_batteryLevelRight = 70,
					device_batteryLevelCase = "0%",
				},
			},
			{ Invalid = { device_address = c, device_batteryLevelMain = "101%", device_batteryLevelLeft = "unknown" } },
		}),
		0
	)
	equal(bt.battery_label(native.devices[1]), nil)
	equal(bt.battery_label(native.devices[2]), "75%")
	equal(bt.battery_label(native.devices[3]), "L 80% · R 70% · Case 0%")
	equal(bt.battery_label({ battery = 0 }), "0%")
	equal(bt.battery_label({ battery = math.huge }), nil)
	equal(bt.battery_label({ battery = 0 / 0 }), nil)
	equal(bt.battery_label({ battery = -1 }), nil)
	equal(bt.battery_label({}), nil)
end)

test("battery enrichment never guesses a match from a redacted or similar name", function()
	local input = { device(a, "Keyboard", true, true), device(b, "Mouse", true, true) }
	local enriched = bt.with_batteries(input, { { name = "Keyboard", battery = 99 }, { address = b, battery = 55 } })
	equal(enriched[1].battery, nil)
	equal(enriched[2].battery, 55)
	equal(input[2].battery, nil)
end)

test("grouping prioritizes connected, then remembered, then nearby without duplicates", function()
	local groups = bt.groups(
		{ device(a, "Keyboard", false, true), device(b, "Headphones", false, true) },
		{ device(a, "Keyboard", true, true) },
		{
			device(a, "Keyboard", true, true),
			device(b, "Headphones", false, false),
			device(c, "New speaker", false, false),
		},
		{ { address = a, battery = 70 } }
	)
	equal(#groups.connected, 1)
	equal(groups.connected[1].address, a)
	equal(groups.connected[1].battery, 70)
	equal(#groups.known, 1)
	equal(groups.known[1].address, b)
	equal(#groups.nearby, 1)
	equal(groups.nearby[1].address, c)
end)

test("fallback groups retain distinct read-only names and safely accept unavailable lists", function()
	local groups = bt.groups({
		{ name = "Keyboard", connected = true, paired = true },
		{ name = "Mouse", connected = true, paired = true },
	})
	equal(#groups.connected, 2)
	equal(groups.connected[1].name, "Keyboard")
	equal(groups.connected[1].address, nil)
	groups = bt.groups(nil, nil, nil)
	equal(#groups.connected, 0)
	equal(#groups.known, 0)
	equal(#groups.nearby, 0)
end)

print("PASS: " .. total .. " Bluetooth control tests")
