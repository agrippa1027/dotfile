local utils = require("lib.utils")

local M = {}

M.providers = {
	{ id = "automatic", label = "Automatic", addresses = {} },
	{
		id = "cloudflare",
		label = "Cloudflare",
		addresses = { "1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001" },
	},
	{
		id = "google",
		label = "Google",
		addresses = { "8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844" },
	},
	{ id = "quad9", label = "Quad9", addresses = { "9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9" } },
}

local function finite(value)
	return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function words(line)
	local values = {}
	for value in line:gmatch("%S+") do
		values[#values + 1] = value
	end
	return values
end

-- Read the link row only: netstat repeats the same counters for each IP address.
-- Column offsets from the right also handle interfaces without a MAC address.
function M.counters(raw, interface)
	if type(raw) ~= "string" or type(interface) ~= "string" then
		return nil
	end
	local columns
	for line in raw:gmatch("[^\r\n]+") do
		local row = words(line)
		if row[1] == "Name" then
			columns = {}
			for index, key in ipairs(row) do
				columns[key] = index - #row
			end
		elseif columns and row[1] and row[1]:gsub("%*$", "") == interface then
			local link = false
			for _, value in ipairs(row) do
				link = link or value:match("^<Link#%d+>$") ~= nil
			end
			if link and columns.Ibytes and columns.Obytes then
				local rx = tonumber(row[#row + columns.Ibytes])
				local tx = tonumber(row[#row + columns.Obytes])
				if finite(rx) and finite(tx) then
					return { interface = interface, rx_bytes = rx, tx_bytes = tx }
				end
			end
		end
	end
	return nil
end

function M.rates(current, previous, now, previous_time)
	if type(current) ~= "table" or type(previous) ~= "table" then
		return nil
	end
	if current.interface ~= previous.interface or type(current.interface) ~= "string" then
		return nil
	end
	for _, key in ipairs({ "rx_bytes", "tx_bytes" }) do
		if not finite(current[key]) or not finite(previous[key]) or current[key] < previous[key] then
			return nil
		end
	end
	if not finite(now) or not finite(previous_time) then
		return nil
	end
	local elapsed = now - previous_time
	-- Treat a stale sample (sleep, missed callback, closed panel) as a fresh start.
	if elapsed <= 0 or elapsed > 30 then
		return nil
	end
	return {
		download = (current.rx_bytes - previous.rx_bytes) / elapsed,
		upload = (current.tx_bytes - previous.tx_bytes) / elapsed,
	}
end

function M.format_bytes(value)
	if not finite(value) then
		return "--"
	end
	local units = { "B", "KiB", "MiB", "GiB", "TiB" }
	local index = 1
	while value >= 1024 and index < #units do
		value = value / 1024
		index = index + 1
	end
	return index == 1 and string.format("%.0f B", value) or string.format("%.1f %s", value, units[index])
end

function M.format_rate(value)
	local label = M.format_bytes(value)
	return label == "--" and label or label .. "/s"
end

-- Service names can be renamed and are not necessarily the hardware-port label.
function M.service(raw, interface)
	if type(raw) ~= "string" or type(interface) ~= "string" then
		return nil
	end
	local name, enabled
	for line in raw:gmatch("[^\r\n]+") do
		local order, service = line:match("^%(([%d*]+)%)%s*(.+)$")
		if order then
			name = utils.trim(service)
			enabled = order ~= "*" and name:sub(1, 1) ~= "*"
		elseif line:match("^%(Hardware Port:") and name then
			local device = line:match("Device:%s*([^%)%s]+)%s*%)")
			if device == interface and enabled then
				return name
			end
			name, enabled = nil, nil
		end
	end
	return nil
end

local function ipv4(address)
	if type(address) ~= "string" or not address:match("^%d+%.%d+%.%d+%.%d+$") then
		return nil
	end
	local octets = {}
	for value in address:gmatch("%d+") do
		local number = tonumber(value)
		if #value > 3 or (#value > 1 and value:sub(1, 1) == "0") or number > 255 then
			return nil
		end
		octets[#octets + 1] = number
	end
	return octets
end

-- Normalize IPv6 spelling so expanded addresses still identify their provider.
local function canonical(address)
	local octets = ipv4(address)
	if octets then
		return table.concat(octets, ".")
	end
	if type(address) ~= "string" then
		return nil
	end
	local zone = address:match("%%([%w_.%-]+)$")
	local body = zone and address:sub(1, #address - #zone - 1) or address
	if not body:match("^[%x:%.]+$") or not body:find(":", 1, true) or body:find(":::", 1, true) then
		return nil
	end
	local tail = body:match("(%d+%.%d+%.%d+%.%d+)$")
	if tail then
		local parts = ipv4(tail)
		if not parts then
			return nil
		end
		body = body:sub(1, #body - #tail)
			.. string.format("%x:%x", parts[1] * 256 + parts[2], parts[3] * 256 + parts[4])
	end
	local compression = body:find("::", 1, true)
	if compression and body:find("::", compression + 2, true) then
		return nil
	end
	if (body:sub(1, 1) == ":" and body:sub(1, 2) ~= "::") or (body:sub(-1) == ":" and body:sub(-2) ~= "::") then
		return nil
	end
	local left = compression and body:sub(1, compression - 1) or body
	local right = compression and body:sub(compression + 2) or ""
	local groups, suffix = {}, {}
	for index, section in ipairs({ left, right }) do
		local target = index == 1 and groups or suffix
		for group in section:gmatch("[^:]+") do
			if #group > 4 or not group:match("^%x+$") then
				return nil
			end
			target[#target + 1] = string.format("%04x", tonumber(group, 16))
		end
	end
	local count = #groups + #suffix
	if compression then
		if count >= 8 then
			return nil
		end
		for _ = 1, 8 - count do
			groups[#groups + 1] = "0000"
		end
	elseif count ~= 8 then
		return nil
	end
	for _, group in ipairs(suffix) do
		groups[#groups + 1] = group
	end
	return table.concat(groups, ":") .. (zone and "%" .. zone:lower() or "")
end

function M.valid_address(address)
	return canonical(address) ~= nil
end

function M.parse_addresses(raw)
	if type(raw) ~= "string" then
		return nil, "Enter DNS server IP addresses"
	end
	local addresses, seen = {}, {}
	for address in raw:gmatch("[^,%s]+") do
		local key = canonical(address)
		if not key then
			return nil, "Invalid DNS server address"
		end
		if not seen[key] then
			addresses[#addresses + 1] = address
			seen[key] = true
		end
	end
	if #addresses == 0 or #addresses > 8 then
		return nil, "Enter between 1 and 8 DNS server addresses"
	end
	return addresses
end

function M.validate_addresses(value)
	if type(value) == "table" then
		local count = 0
		for key, address in pairs(value) do
			if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or not canonical(address) then
				return nil, "Invalid DNS server address"
			end
			count = count + 1
		end
		if count ~= #value then
			return nil, "Invalid DNS server address"
		end
		value = table.concat(value, " ")
	end
	return M.parse_addresses(value)
end

-- Compare the complete readback, not just the recognized provider: a partial
-- Cloudflare list must not verify a request to install all four addresses.
function M.same_dns(a, b)
	local function address_set(value)
		if type(value) ~= "table" or value.provider == "unavailable" then
			return nil
		end
		local addresses = value.addresses or value
		if type(addresses) ~= "table" then
			return nil
		end
		local result, count = {}, 0
		for index, address in pairs(addresses) do
			local key = canonical(address)
			if type(index) ~= "number" or index < 1 or index % 1 ~= 0 or not key then
				return nil
			end
			result[key] = true
			count = count + 1
		end
		return count == #addresses and result or nil
	end
	local left, right = address_set(a), address_set(b)
	if not left or not right then
		return false
	end
	for key in pairs(left) do
		if not right[key] then
			return false
		end
	end
	for key in pairs(right) do
		if not left[key] then
			return false
		end
	end
	return true
end

function M.dns(raw, status)
	local result = { provider = "unavailable", addresses = {} }
	if status ~= 0 or type(raw) ~= "string" then
		return result
	end
	if utils.trim(raw):match("^There aren't any DNS Servers set on .+") then
		result.provider = "automatic"
		return result
	end
	local addresses = M.parse_addresses(raw)
	if not addresses then
		return result
	end
	result.addresses = addresses
	result.provider = "custom"
	for _, provider in ipairs(M.providers) do
		if #provider.addresses > 0 then
			local known, matches = {}, true
			for _, address in ipairs(provider.addresses) do
				known[canonical(address)] = true
			end
			for _, address in ipairs(addresses) do
				matches = matches and known[canonical(address)] == true
			end
			if matches then
				result.provider = provider.id
				break
			end
		end
	end
	return result
end

function M.dns_command(service, provider_id, custom_addresses)
	if type(service) ~= "string" or service == "" or service:find("%c") then
		return nil, "Network service is unavailable"
	end
	local addresses
	if provider_id == "custom" then
		local message
		addresses, message = M.validate_addresses(custom_addresses)
		if not addresses then
			return nil, message
		end
	else
		for _, provider in ipairs(M.providers) do
			if provider.id == provider_id then
				addresses = provider.addresses
				break
			end
		end
	end
	if not addresses then
		return nil, "Unknown DNS provider"
	end
	local parts = { "/usr/sbin/networksetup -setdnsservers", utils.quote(service) }
	if #addresses == 0 then
		parts[#parts + 1] = "Empty"
	else
		for _, address in ipairs(addresses) do
			parts[#parts + 1] = utils.quote(address)
		end
	end
	return table.concat(parts, " ")
end

function M.power_command(interface, enabled)
	if type(interface) ~= "string" or not interface:match("^[%a][%w]*$") or type(enabled) ~= "boolean" then
		return nil, "Wi-Fi interface is unavailable"
	end
	return "/usr/sbin/networksetup -setairportpower " .. utils.quote(interface) .. (enabled and " on" or " off")
end

function M.ping(raw, status)
	if type(raw) ~= "string" then
		return nil
	end
	local loss = tonumber(raw:match("([%d.]+)%%%s*packet loss"))
	local latency = tonumber(raw:match("time[=<]([%d.]+)%s*ms"))
	local average = raw:match("round%-trip min/avg/max/[%w%-]+ = [%d.]+/([%d.]+)/")
	latency = tonumber(average) or latency
	if status ~= 0 and not loss then
		return nil
	end
	if loss and (not finite(loss) or loss > 100) then
		return nil
	end
	if not finite(latency) and loss ~= 100 then
		return nil
	end
	return { latency = finite(latency) and latency or nil, loss = loss }
end

return M
