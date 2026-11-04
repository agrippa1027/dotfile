local sbar = require("sketchybar")
local colors = require("colors")
local settings = require("settings")
local utils = require("lib.utils")
local controls = require("lib.network_controls")

local M = {}

function M.attach(owner, options)
	local width = settings.popup.network_width
	local half = width / 2 - 5
	local graph_points = math.floor(half - 10)
	local prefix = owner.name .. "."
	local panel = {}
	local opened, generation = false, 0
	local previous, previous_time, service, dns
	local sampling, sample_started, last_ping, ping_revision = false, 0, 0, 0
	local busy, action_started, action_revision, executing = false, 0, 0, false
	local dns_revision, prompt_open = 0, false
	local restore
	local root = os.getenv("CONFIG_DIR")
	local restore_path = root and root .. "/runtime/network-dns-previous"

	local function item(name, label, full, color)
		return sbar.add("item", prefix .. name, {
			position = "popup." .. owner.name,
			width = full and width or half,
			cell_span = full and 2 or 1,
			align = "center",
			icon = { drawing = false },
			label = {
				string = label,
				color = color or colors.white,
				font = { size = 12 },
				max_chars = full and 48 or 23,
			},
		})
	end

	local down = item("download", "↓  Sampling…", false, colors.accent)
	local up = item("upload", "↑  Sampling…", false, colors.blue)
	local graphs = {}
	for index, name in ipairs({ "download", "upload" }) do
		graphs[index] = sbar.add("graph", prefix .. name .. ".history", graph_points, {
			position = "popup." .. owner.name,
			width = half,
			cell_span = 1,
			icon = { drawing = false },
			label = { drawing = false },
			graph = { color = index == 1 and colors.accent or colors.blue, line_width = 1.5 },
			background = { height = 24, color = colors.bg1, corner_radius = 4 },
		})
	end
	item("history.caption", "Traffic history · 10 MiB/s scale", true, colors.grey)
	local router_ping = item("router.ping", "Router  —", false)
	local internet_ping = item("internet.ping", "Internet  —", false)
	local received = item("received", "Received  —", false, colors.grey)
	local sent = item("sent", "Sent  —", false, colors.grey)
	local dns_heading = item("dns.heading", "DNS · Checking…", true, colors.accent)
	local providers = {}
	for _, provider in ipairs(controls.providers) do
		providers[provider.id] = item("dns." .. provider.id, provider.label, false)
	end
	local custom = item("dns.custom", "Custom DNS…", false, colors.blue)
	local restore_item = item("dns.restore", "Restore previous", false, colors.grey)
	local status = item("action.status", "DNS applies to this Wi-Fi service", true, colors.grey)
	local power = item("power", "Wi-Fi power…", false, colors.blue)
	local detail_toggle = item("details", "Connection details  ▾", false, colors.grey)
	local speed = item("speedtest", "Run speed test · uses internet data", true, colors.blue)
	local test_down = item("speedtest.download", "", false, colors.accent)
	local test_up = item("speedtest.upload", "", false, colors.blue)
	test_down:set({ drawing = false })
	test_up:set({ drawing = false })

	local timer = sbar.add("item", prefix .. "telemetry", { drawing = false, updates = true, update_freq = 0 })
	owner:set({ popup = { columns = 2 } })

	local function message(text, failed)
		status:set({ label = { string = text, color = failed and colors.red or colors.grey } })
	end

	local function load_restore()
		if not restore_path then
			return
		end
		local file = io.open(restore_path, "r")
		if not file then
			return
		end
		local saved_service, raw = file:read("*l"), file:read("*a")
		file:close()
		if saved_service ~= service then
			return
		end
		local saved = controls.dns(raw, 0)
		if saved.provider ~= "unavailable" then
			restore = saved
		end
	end

	local function save_restore(saved)
		if not restore_path then
			restore = saved
			return true
		end
		local file = io.open(restore_path .. ".tmp", "w")
		if not file then
			return false
		end
		local written = file:write(
			service,
			"\n",
			#saved.addresses == 0 and "There aren't any DNS Servers set on this service.\n"
				or table.concat(saved.addresses, "\n") .. "\n"
		)
		local closed = file:close()
		if not written or not closed or not os.rename(restore_path .. ".tmp", restore_path) then
			return false
		end
		restore = saved
		return true
	end

	local function render_dns()
		local label = "Unavailable"
		if dns and dns.provider == "custom" then
			label = "Custom"
		end
		for _, provider in ipairs(controls.providers) do
			if dns and dns.provider == provider.id then
				label = provider.label
			end
		end
		dns_heading:set({ label = "DNS · " .. label })
		for _, provider in ipairs(controls.providers) do
			local selected = dns and dns.provider == provider.id
			providers[provider.id]:set({
				label = {
					string = (selected and "●  " or "○  ") .. provider.label,
					color = selected and colors.accent or colors.white,
				},
				background = { color = selected and colors.bg2 or colors.transparent },
			})
		end
		restore_item:set({ label = { color = restore and colors.blue or colors.grey } })
	end

	local function read_dns(callback, action_token)
		dns_revision = dns_revision + 1
		local dns_request = dns_revision
		local request, device = generation, options.get_interface()
		local function current()
			if request == generation and dns_request == dns_revision then
				return true
			end
			-- A reopened panel owns a fresh read. Retire the old readback's action
			-- without releasing the guard for a newer mutation.
			if action_token and action_token == action_revision then
				busy = false
			end
			return false
		end
		sbar.exec("/usr/sbin/networksetup -listnetworkserviceorder 2>/dev/null", function(result, exit)
			if not current() then
				return
			end
			local found = exit == 0 and controls.service(result, device)
			if not found then
				service, dns = nil, nil
				render_dns()
				if callback then
					callback(false)
				end
				return
			end
			if found ~= service then
				restore = nil
			end
			service = found
			sbar.exec(
				"/usr/sbin/networksetup -getdnsservers " .. utils.quote(service) .. " 2>/dev/null",
				function(raw, code)
					if not current() then
						return
					end
					dns = controls.dns(raw, code)
					load_restore()
					render_dns()
					if callback then
						callback(dns.provider ~= "unavailable")
					end
				end
			)
		end)
	end

	local function begin_action()
		if busy and os.time() - action_started < 65 then
			return nil
		end
		action_revision = action_revision + 1
		busy, action_started = true, os.time()
		return action_revision
	end

	local function apply_dns(provider, addresses)
		local expected_service = service
		local request = begin_action()
		if not request then
			return
		end
		message("Checking current DNS…")
		read_dns(function(ok)
			if request ~= action_revision then
				return
			end
			if not ok or not service then
				busy = false
				message("Cannot read DNS; no changes made", true)
				return
			end
			if expected_service and service ~= expected_service then
				busy = false
				message("Network service changed; choose DNS again", true)
				return
			end
			local command, err = controls.dns_command(service, provider, addresses)
			if not command then
				busy = false
				message(err or "Invalid DNS addresses", true)
				return
			end
			local before = dns
			local expected = addresses
			if provider ~= "custom" then
				for _, choice in ipairs(controls.providers) do
					if choice.id == provider then
						expected = choice.addresses
					end
				end
			end
			if not restore and not save_restore(before) then
				busy = false
				message("Could not save previous DNS; no changes made", true)
				return
			end
			message("Applying DNS…")
			executing = true
			sbar.exec(command .. " 2>&1", function(_, code)
				if request ~= action_revision then
					return
				end
				executing = false
				if code ~= 0 then
					busy = false
					message("DNS change failed · check macOS permissions", true)
					return
				end
				read_dns(function(verified)
					if request ~= action_revision then
						return
					end
					busy = false
					verified = verified and controls.same_dns(dns, expected)
					message(
						verified and ("DNS updated for " .. service) or "DNS change could not be verified",
						not verified
					)
				end, request)
			end)
		end, request)
	end

	for _, provider in ipairs(controls.providers) do
		providers[provider.id]:subscribe("mouse.clicked", function()
			apply_dns(provider.id)
		end)
	end
	restore_item:subscribe("mouse.clicked", function()
		if restore then
			apply_dns(#restore.addresses == 0 and "automatic" or "custom", restore.addresses)
		end
	end)
	custom:subscribe("mouse.clicked", function()
		if busy or prompt_open then
			return
		end
		prompt_open = true
		sbar.exec(
			[[ /usr/bin/osascript -e 'text returned of (display dialog "Enter DNS server IP addresses, separated by spaces or commas." default answer "" with title "Custom DNS" buttons {"Cancel", "Apply"} default button "Apply")' ]],
			function(raw, code)
				prompt_open = false
				if code ~= 0 or type(raw) ~= "string" then
					return
				end
				local addresses = {}
				for address in raw:gmatch("[^,%s]+") do
					addresses[#addresses + 1] = address
				end
				apply_dns("custom", addresses)
			end
		)
	end)

	local showing_details = false
	detail_toggle:subscribe("mouse.clicked", function()
		showing_details = not showing_details
		for _, row in ipairs(options.detail_items) do
			row:set({ drawing = showing_details })
		end
		detail_toggle:set({ label = showing_details and "Connection details  ▴" or "Connection details  ▾" })
	end)

	power:subscribe("mouse.clicked", function()
		local current = options.get_status()
		local command = current and controls.power_command(options.get_interface(), current.state == "off")
		if not command then
			message("Wi-Fi radio unavailable", true)
			return
		end
		local request = begin_action()
		if not request then
			return
		end
		message("Changing Wi-Fi power…")
		executing = true
		sbar.exec(command .. " 2>&1", function(_, code)
			if request ~= action_revision then
				return
			end
			busy, executing = false, false
			message(code == 0 and "Wi-Fi power updated" or "Wi-Fi power change failed", code ~= 0)
			previous = nil
			options.refresh()
		end)
	end)

	speed:subscribe("mouse.clicked", function()
		local device = options.get_interface()
		if not device then
			message("No Wi-Fi interface available", true)
			return
		end
		local request = begin_action()
		if not request then
			return
		end
		speed:set({ label = "Testing… up to 20 seconds" })
		test_down:set({ drawing = false })
		test_up:set({ drawing = false })
		message("Measuring internet capacity · uses data")
		executing = true
		sbar.exec(
			"/usr/bin/networkQuality -c -M 20 -I " .. utils.quote(device) .. " 2>/dev/null",
			function(result, code)
				if request ~= action_revision then
					return
				end
				busy, executing = false, false
				speed:set({ label = "Run speed test · uses internet data" })
				local download = type(result) == "table" and tonumber(result.dl_throughput)
				local upload = type(result) == "table" and tonumber(result.ul_throughput)
				if
					code ~= 0
					or not download
					or not upload
					or download ~= download
					or upload ~= upload
					or download < 0
					or upload < 0
					or download == math.huge
					or upload == math.huge
				then
					message("Speed test unavailable; try again", true)
					return
				end
				test_down:set({ drawing = true, label = string.format("↓ Test  %.1f Mbps", download / 1000000) })
				test_up:set({ drawing = true, label = string.format("↑ Test  %.1f Mbps", upload / 1000000) })
				message("Speed test complete · " .. os.date("%H:%M"))
			end
		)
	end)

	local function ping(target, row, request, revision)
		if not target then
			row:set({ label = "Router  —" })
			return
		end
		sbar.exec("/sbin/ping -n -c 1 -W 1000 " .. utils.quote(target) .. " 2>/dev/null", function(raw, code)
			if not opened or generation ~= request or ping_revision ~= revision then
				return
			end
			local result = controls.ping(raw, code)
			local label = row == router_ping and "Router" or "Internet"
			row:set({
				label = label
					.. (result and result.latency and string.format("  %.0f ms", result.latency) or "  No reply"),
			})
		end)
	end

	local function sample()
		if not opened then
			return
		end
		local now, device = os.time(), options.get_interface()
		if not device or (sampling and now - sample_started < 8) then
			return
		end
		sampling, sample_started = true, now
		local request = generation
		sbar.exec("/usr/sbin/netstat -ibn -I " .. utils.quote(device) .. " 2>/dev/null", function(raw, code)
			if not opened or generation ~= request or sample_started ~= now then
				return
			end
			sampling = false
			local current = code == 0 and controls.counters(raw, device)
			local sampled_at = os.time()
			local rate = current and controls.rates(current, previous, sampled_at, previous_time)
			previous, previous_time = current, sampled_at
			down:set({ label = rate and ("↓  " .. controls.format_rate(rate.download)) or "↓  Sampling…" })
			up:set({ label = rate and ("↑  " .. controls.format_rate(rate.upload)) or "↑  Sampling…" })
			received:set({
				label = current and ("Received  " .. controls.format_bytes(current.rx_bytes)) or "Received  —",
			})
			sent:set({ label = current and ("Sent  " .. controls.format_bytes(current.tx_bytes)) or "Sent  —" })
			if rate then
				graphs[1]:push({ math.min(rate.download / (10 * 1024 * 1024), 1) })
				graphs[2]:push({ math.min(rate.upload / (10 * 1024 * 1024), 1) })
			end
		end)
		if now - last_ping >= 10 then
			last_ping, ping_revision = now, ping_revision + 1
			local current = options.get_status()
			ping(current and current.router, router_ping, request, ping_revision)
			ping("1.1.1.1", internet_ping, request, ping_revision)
		end
	end
	timer:subscribe("routine", sample)

	function panel:open()
		opened, generation = true, generation + 1
		previous, previous_time, sampling, last_ping = nil, nil, false, 0
		down:set({ label = "↓  Sampling…" })
		up:set({ label = "↑  Sampling…" })
		local empty = {}
		for index = 1, graph_points do
			empty[index] = 0
		end
		for _, graph in ipairs(graphs) do
			graph:push(empty)
		end
		timer:set({ update_freq = 2 })
		read_dns()
		sample()
	end
	function panel:close()
		opened, generation, sampling = false, generation + 1, false
		if not executing then
			busy, action_revision = false, action_revision + 1
		end
		timer:set({ update_freq = 0 })
	end
	function panel:status(current)
		power:set({ label = current.state == "off" and "Turn Wi-Fi on" or "Turn Wi-Fi off" })
	end
	return panel
end

return M
