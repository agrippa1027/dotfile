local utils = require("lib.utils")

local M = {}
M.binary = "/opt/homebrew/bin/blueutil"

function M.address(value)
	if type(value) ~= "string" then
		return nil
	end
	local compact
	if value:match("^%x%x%x%x%x%x%x%x%x%x%x%x$") then
		compact = value
	elseif value:match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") or value:match("^%x%x%-%x%x%-%x%x%-%x%x%-%x%x%-%x%x$") then
		compact = value:gsub("[:-]", "")
	else
		return nil
	end
	local parts = {}
	for part in compact:lower():gmatch("%x%x") do
		parts[#parts + 1] = part
	end
	return table.concat(parts, ":")
end

function M.command(action, value)
	if action == "power" then
		if value == nil then
			return M.binary .. " --power"
		elseif type(value) == "boolean" then
			return M.binary .. " --power " .. (value and "1" or "0")
		end
		return nil, "Bluetooth power must be on or off"
	elseif action == "paired" or action == "connected" or action == "inquiry" then
		if value ~= nil then
			return nil, "Unexpected Bluetooth argument"
		end
		-- IOBluetooth's paired-device objects can misreport multipoint audio links.
		-- Use macOS's report for snapshots; leave scan and mutation APIs unchanged.
		local reader = action == "inquiry" and M.binary or "/usr/bin/env BLUEUTIL_USE_SYSTEM_PROFILER=1 " .. M.binary
		return reader .. (action == "inquiry" and " --inquiry 8" or " --" .. action) .. " --format json"
	elseif
		action == "info"
		or action == "connect"
		or action == "disconnect"
		or action == "pair"
		or action == "unpair"
	then
		local address = M.address(value)
		if not address then
			return nil, "Invalid Bluetooth device address"
		end
		return M.binary
			.. " --"
			.. action
			.. " "
			.. utils.quote(address)
			.. (action == "info" and " --format json" or "")
	end
	return nil, "Unknown Bluetooth action"
end

function M.power(raw, status)
	if status ~= 0 or type(raw) ~= "string" then
		return nil
	end
	local value = raw:match("^%s*([01])%s*$")
	if value then
		return value == "1"
	end
	return nil
end

local function flag(value)
	if type(value) == "boolean" then
		return value
	elseif value == 1 then
		return true
	elseif value == 0 then
		return false
	end
	return nil
end

local function percent(value)
	if type(value) == "string" then
		value = value:match("^%s*(%d+%.?%d*)%%?%s*$")
	end
	value = tonumber(value)
	if value and value == value and value >= 0 and value <= 100 then
		return math.floor(value + 0.5)
	end
end

local function label(value, fallback)
	if type(value) ~= "string" then
		return fallback
	end
	value = utils.trim(value:gsub("[%c]", " "):gsub("%s+", " "))
	return value ~= "" and value or fallback
end

local function sorted(list)
	table.sort(list, function(a, b)
		local an, bn = a.name:lower(), b.name:lower()
		if an ~= bn then
			return an < bn
		end
		return (a.address or "") < (b.address or "")
	end)
	return list
end

function M.device(raw, status)
	if status ~= 0 or type(raw) ~= "table" then
		return nil
	end
	local address = M.address(raw.address)
	if
		not address
		or (raw.connected ~= nil and flag(raw.connected) == nil)
		or (raw.paired ~= nil and flag(raw.paired) == nil)
	then
		return nil
	end
	return {
		address = address,
		name = label(raw.name, address),
		connected = flag(raw.connected),
		paired = flag(raw.paired),
	}
end

function M.devices(raw, status)
	if status ~= 0 or type(raw) ~= "table" then
		return nil
	end
	local count = 0
	for key in pairs(raw) do
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
			return nil
		end
		count = count + 1
	end
	if count ~= #raw then
		return nil
	end
	local result, seen = {}, {}
	for _, value in ipairs(raw) do
		local device = M.device(value, 0)
		if device then
			local existing = seen[device.address]
			if existing then
				for _, key in ipairs({ "connected", "paired" }) do
					if device[key] ~= nil then
						existing[key] = existing[key] or device[key]
					end
				end
				if existing.name == existing.address then
					existing.name = device.name
				end
			else
				seen[device.address] = device
				result[#result + 1] = device
			end
		end
	end
	if count > 0 and #result == 0 then
		return nil
	end
	return sorted(result)
end

function M.find_device(raw, status, address)
	address = M.address(address)
	local devices = address and M.devices(raw, status)
	for _, device in ipairs(devices or {}) do
		if device.address == address then
			return device
		end
	end
end

function M.profiler(raw, status)
	local result = { devices = {} }
	local entries = status == 0 and type(raw) == "table" and raw.SPBluetoothDataType
	local data = type(entries) == "table" and entries[1]
	local controller = type(data) == "table" and data.controller_properties
	local state = type(controller) == "table" and controller.controller_state
	if state == "attrib_on" then
		result.powered = true
	elseif state == "attrib_off" then
		result.powered = false
	end
	if result.powered ~= true or type(data) ~= "table" then
		return result
	end
	for _, source in ipairs({ { "device_connected", true }, { "device_not_connected", false } }) do
		local devices = data[source[1]]
		if type(devices) == "table" then
			for _, wrapper in ipairs(devices) do
				if type(wrapper) == "table" then
					for name, properties in pairs(wrapper) do
						if type(name) == "string" and type(properties) == "table" then
							local parts = {}
							for _, part in ipairs({ "Left", "Right", "Case" }) do
								parts[part:lower()] = percent(properties["device_batteryLevel" .. part])
							end
							result.devices[#result.devices + 1] = {
								address = M.address(properties.device_address),
								name = label(name, "Unnamed device"),
								connected = source[2],
								paired = true,
								low_energy = type(properties.device_services) == "string"
									and properties.device_services:match("%f[%a]BLE%f[%A]") ~= nil,
								battery = percent(properties.device_batteryLevelMain),
								battery_parts = next(parts) and parts or nil,
							}
						end
					end
				end
			end
		end
	end
	result.devices = sorted(result.devices)
	return result
end

function M.battery_label(device)
	if type(device) ~= "table" then
		return nil
	end
	local main = percent(device.battery)
	if main then
		return main .. "%"
	end
	local parts, values = type(device.battery_parts) == "table" and device.battery_parts or {}, {}
	for _, part in ipairs({ { "left", "L" }, { "right", "R" }, { "case", "Case" } }) do
		local value = percent(parts[part[1]])
		if value then
			values[#values + 1] = part[2] .. " " .. value .. "%"
		end
	end
	return #values > 0 and table.concat(values, " · ") or nil
end

function M.with_batteries(devices, profiler_devices)
	local batteries, result = {}, {}
	for _, device in ipairs(profiler_devices or {}) do
		if device.address then
			batteries[device.address] = device
		end
	end
	for _, device in ipairs(devices or {}) do
		local copy = {}
		for key, value in pairs(device) do
			copy[key] = value
		end
		local battery = copy.address and batteries[copy.address]
		if battery then
			copy.battery, copy.battery_parts = battery.battery, battery.battery_parts
		end
		result[#result + 1] = copy
	end
	return result
end

function M.groups(paired, connected, nearby, profiler_devices)
	local merged, ordered = {}, {}
	for index, list in ipairs({ paired or {}, connected or {}, nearby or {} }) do
		for _, device in ipairs(list) do
			local key = device.address or ("name:" .. device.name)
			local row = merged[key]
			if not row then
				row = {}
				for field, value in pairs(device) do
					row[field] = value
				end
				merged[key] = row
				ordered[#ordered + 1] = row
			end
			row.paired = row.paired or device.paired or index == 1
			row.connected = row.connected or device.connected or index == 2
		end
	end
	local result = { connected = {}, known = {}, nearby = {} }
	for _, device in ipairs(M.with_batteries(ordered, profiler_devices)) do
		local group = device.connected and "connected" or device.paired and "known" or "nearby"
		result[group][#result[group] + 1] = device
	end
	for _, list in pairs(result) do
		sorted(list)
	end
	return result
end

return M
