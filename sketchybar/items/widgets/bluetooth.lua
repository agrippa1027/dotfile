local sbar = require("sketchybar")
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local popup = require("lib.popup")
local ui = require("lib.panel")
local utils = require("lib.utils")
local controls = require("lib.bluetooth_controls")

local width = settings.popup.width + 80
local gap = settings.popup.gap
local function span_width(span)
	return (width - 5 * gap) / 6 * span + (span - 1) * gap
end
local bluetooth = sbar.add("item", "widgets.bluetooth", {
	position = "right",
	update_freq = 60,
	icon = { string = icons.bluetooth, color = colors.grey },
	label = { drawing = false },
	background = { color = colors.transparent },
	popup = {
		align = "right",
		height = 1,
		columns = 6,
		blur_radius = 0,
		background = {
			color = colors.popup.bg,
			border_color = colors.accent,
			border_width = settings.popup.border_width,
			corner_radius = settings.popup.corner_radius,
		},
	},
})
local styles = {}
local function row(name, label, span, color)
	span = span or 6
	return sbar.add("item", "widgets.bluetooth." .. name, {
		position = "popup." .. bluetooth.name,
		width = span_width(span),
		cell_span = span,
		align = "center",
		icon = { drawing = false },
		label = {
			string = label,
			color = color or colors.white,
			max_chars = 55,
			font = { family = settings.font.text, style = settings.font.style_map.Regular, size = 11 },
			padding_left = 4,
			padding_right = 4,
		},
		background = { height = settings.popup.height, padding_left = 0, padding_right = 0 },
	})
end
local function action(item, enabled)
	local style = ui.action(item, { enabled = enabled ~= false })
	styles[#styles + 1] = style
	return style
end
local heading = row("heading", "Bluetooth")
ui.heading(heading)
local status = row("status", "Checking…", 6, colors.grey)
local power_button = row("power", "Checking power…", 3)
local power_style = action(power_button, false)
local scan_button = row("scan", "Scan nearby · 8s", 3)
local scan_style = action(scan_button, false)
local sections, slots = {}, {}
for _, group in ipairs({ "connected", "known", "nearby" }) do
	sections[group] = row(group .. ".heading", "")
	ui.section(sections[group])
	slots[group] = {}
	for index = 1, 4 do
		local prefix = group .. "." .. index
		local info = row(prefix .. ".info", "", 3)
		info:set({ label = { align = "left", width = span_width(3) - 8, max_chars = 26 } })
		local button = row(prefix .. ".action", "", 2)
		local forget = row(prefix .. ".forget", "Forget", 1, colors.grey)
		forget:set({ label = { font = { size = 10 } } })
		slots[group][index] = {
			info = info,
			button = button,
			forget = forget,
			button_style = action(button, false),
			forget_style = action(forget, false),
		}
	end
end
local empty = row("empty", "Checking devices…", 6, colors.grey)
local message_item = row("message", "", 6, colors.grey)
message_item:set({ drawing = false, label = { font = { size = 10 } } })
local refresh_button = row("refresh", "Refresh", 3, colors.grey)
local refresh_style = action(refresh_button)
local settings_button = row("settings", "Bluetooth Settings ↗", 3, colors.blue)
action(settings_button)
local audio_button = row("audio", "Audio outputs →", 6, colors.blue)
action(audio_button)
local timer = sbar.add("item", "widgets.bluetooth.timer", { drawing = false, updates = true, update_freq = 0 })

local opened, session = false, 0
local powered, available
local paired, connected, nearby, batteries = {}, {}, {}, {}
local scanned, scanning, scan_revision, scan_started = false, false, 0, 0
local read_revision, read_started, pending_read = 0, nil, false
local action_revision = 0
---@type {token: integer, kind: string, address: string?, caption: string, started: integer, session: integer, phase: string, allow_closed: boolean?}|nil
local current_action
local refresh, details
local power_command = "/usr/bin/defaults read /Library/Preferences/com.apple.Bluetooth ControllerPowerState 2>/dev/null"
local profiler_command = "/usr/sbin/system_profiler SPBluetoothDataType -json -detailLevel mini 2>/dev/null"

local function message(text, failed)
	message_item:set({ drawing = true, label = { string = text, color = failed and colors.red or colors.grey } })
end
local function system_managed(device)
	if not device then
		return false
	end
	local matches, low_energy = 0, false
	for _, reported in ipairs(batteries) do
		-- Names only restrict capabilities when macOS redacts the address;
		-- they never identify a target for a hardware mutation.
		if
			reported.address == device.address and device.address ~= nil
			or not reported.address and reported.name == device.name
		then
			matches, low_energy = matches + 1, reported.low_energy == true
		end
	end
	return matches == 1 and low_energy
end
local function render()
	bluetooth:set({ icon = { color = powered and colors.white or colors.grey } })
	if not opened then
		return
	end
	local groups = controls.groups(
		controls.with_batteries(paired, batteries),
		controls.with_batteries(connected, batteries),
		nearby
	)
	status:set({
		label = {
			string = powered == nil and "Bluetooth unavailable"
				or (not powered and "Bluetooth is off")
				or string.format("%d connected · %d remembered", #groups.connected, #groups.known),
			color = powered and #groups.connected > 0 and colors.accent or colors.grey,
		},
	})
	power_button:set({
		label = powered == nil and "Power unavailable" or (powered and "Turn Bluetooth off" or "Turn Bluetooth on"),
	})
	power_style:enable(available == true and powered ~= nil and not current_action and not scanning)
	scan_button:set({ label = scanning and "Scanning…" or "Scan nearby · 8s" })
	scan_style:enable(available == true and powered == true and not current_action and not scanning)
	refresh_style:enable(not current_action and not scanning)
	for _, group in ipairs({ "connected", "known", "nearby" }) do
		local list = powered and groups[group] or {}
		local caption = ({ connected = "CONNECTED", known = "REMEMBERED", nearby = "NEARBY" })[group]
		sections[group]:set({
			drawing = #list > 0,
			label = caption .. (#list > 4 and " · 4 / " .. #list .. " · MORE IN SETTINGS" or ""),
		})
		for index, slot in ipairs(slots[group]) do
			local device = list[index]
			slot.device = device
			slot.system_managed = system_managed(device)
			local battery = device and controls.battery_label(device)
			slot.info:set({
				drawing = device ~= nil,
				label = {
					string = device and (device.name .. (battery and " · " .. battery or "")) or "",
					color = group == "connected" and colors.white or colors.grey,
				},
			})
			local busy = device and current_action and current_action.address == device.address
			local label = busy and current_action and current_action.caption
				or slot.system_managed and "Settings ↗"
				or group == "nearby" and "Pair in Settings"
				or group == "connected" and "Disconnect"
				or "Connect"
			slot.button:set({ drawing = device ~= nil, label = label })
			slot.forget:set({
				drawing = device ~= nil,
				label = group ~= "nearby" and not slot.system_managed and "Forget" or "",
			})
			local actionable = device and available and controls.address(device.address) ~= nil
			slot.button_style:enable(
				device ~= nil and not current_action and not scanning and (group == "nearby" or actionable == true)
			)
			slot.forget_style:enable(
				group ~= "nearby"
					and not slot.system_managed
					and actionable == true
					and not current_action
					and not scanning
			)
			if not actionable and group ~= "nearby" then
				slot.button:set({ label = "Use Settings" })
			end
		end
	end
	local count = #groups.connected + #groups.known + #groups.nearby
	empty:set({
		drawing = not powered or count == 0,
		label = powered == nil and "Check Bluetooth access in System Settings"
			or not powered and "Turn on Bluetooth to use your accessories"
			or scanned and "No nearby devices found · Try pairing mode"
			or "No devices found · Scan nearby or open Settings",
	})
end

local function finish_action(token, text, failed)
	if not current_action or current_action.token ~= token then
		return
	end
	local show = opened and current_action.session == session
	current_action = nil
	if show and text then
		message(text, failed)
	end
	render()
	if opened then
		refresh()
	end
end
local function begin_action(kind, address, caption)
	if not opened or not available or scanning then
		return
	end
	if current_action then
		if os.time() - current_action.started < 65 then
			return
		end
		current_action = nil
	end
	-- Inventory sampled before this action must not replace its verified state.
	read_revision, read_started, pending_read = read_revision + 1, nil, false
	action_revision = action_revision + 1
	current_action = {
		token = action_revision,
		kind = kind,
		address = address,
		caption = caption,
		started = os.time(),
		session = session,
		phase = "preflight",
	}
	message_item:set({ drawing = false })
	render()
	return action_revision
end
local function action_current(token)
	return current_action and current_action.token == token
end
local function exec_action(token, command, callback)
	if not action_current(token) then
		return
	end
	current_action.started = os.time()
	sbar.exec(command .. " 2>/dev/null", function(raw, code)
		if action_current(token) then
			callback(raw, code)
		end
	end)
end
local function confirm(token, text, button, callback)
	current_action.phase = "confirm"
	local script = "button returned of (display dialog "
		.. '"'
		.. text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("[\r\n]", " ")
		.. '"'
		.. ' with title "Bluetooth" buttons {"Cancel", "'
		.. button
		.. '"} default button "Cancel")'
	sbar.exec("/usr/bin/osascript -e " .. utils.quote(script), function(raw, code)
		if not action_current(token) then
			return
		end
		if code ~= 0 or type(raw) ~= "string" or utils.trim(raw) ~= button then
			finish_action(token, "Cancelled")
			return
		end
		-- Native confirmation may dismiss the popup; the explicit confirmation
		-- still authorizes this captured target, followed by a fresh preflight.
		current_action.allow_closed = true
		current_action.phase = "preflight"
		callback()
	end)
end
local function device_action(device, kind)
	local address = controls.address(device and device.address)
	if not address then
		return
	end
	local token = begin_action(
		kind,
		address,
		kind == "connect" and "Connecting…" or kind == "disconnect" and "Disconnecting…" or "Forgetting…"
	)
	if not token then
		return
	end
	local function preflight()
		exec_action(token, assert(controls.command("paired")), function(raw, code)
			local fresh = controls.find_device(raw, code, address)
			if not fresh or fresh.address ~= address or fresh.connected == nil or fresh.paired == nil then
				finish_action(token, "Device status unavailable; no changes made", true)
				return
			end
			if kind == "connect" and fresh.paired ~= true then
				finish_action(token, "Pair this device in Bluetooth Settings first", true)
				return
			end
			if kind == "disconnect" and fresh.connected ~= true then
				finish_action(token, "Device is already disconnected")
				return
			end
			if kind == "unpair" and fresh.paired ~= true then
				finish_action(token, "Device is already forgotten")
				return
			end
			current_action.phase = "executing"
			exec_action(token, assert(controls.command(kind, address)), function(_, result)
				if result ~= 0 then
					finish_action(token, "Bluetooth action failed · Try Settings", true)
					return
				end
				current_action.phase = "readback"
				-- macOS reports can lag a completed mutation; retry reads only.
				local attempts, started = 0, os.time()
				local function verify()
					attempts = attempts + 1
					local command = assert(controls.command("paired"))
					if attempts > 1 then
						command = "/bin/sleep 0.5; " .. command
					end
					exec_action(token, command, function(report, exit)
						local verified = false
						if kind == "unpair" then
							local list = controls.devices(report, exit)
							verified = list ~= nil
							for _, item in ipairs(list or {}) do
								if item.address == address then
									verified = false
								end
							end
						else
							local info = controls.find_device(report, exit, address)
							verified = info ~= nil and info.address == address and info.connected == (kind == "connect")
						end
						if not verified and exit == 0 and attempts < 10 and os.time() - started < 10 then
							verify()
							return
						end
						finish_action(
							token,
							verified
									and (kind == "unpair" and "Device forgotten" or kind == "connect" and "Device connected" or "Device disconnected")
								or "Change could not be verified · Refresh or use Settings",
							not verified
						)
					end)
				end
				verify()
			end)
		end)
	end
	if kind == "unpair" then
		confirm(token, "Forget " .. device.name .. "? You will need to pair it again.", "Forget", preflight)
	else
		preflight()
	end
end

refresh = function()
	if current_action then
		pending_read = true
		return
	end
	local now = os.time()
	if read_started and now - read_started < 65 then
		pending_read = true
		return
	end
	read_revision = read_revision + 1
	local request, view, detailed = read_revision, session, opened
	read_started, pending_read = now, false
	local function visible()
		return detailed and opened and session == view
	end
	local function finish()
		if request ~= read_revision then
			return
		end
		read_started = nil
		if pending_read then
			refresh()
		end
	end
	local function exec(command, callback)
		read_started = os.time()
		sbar.exec(command, function(raw, code)
			if request == read_revision then
				callback(raw, code)
			end
		end)
	end
	local function fallback()
		exec(profiler_command, function(raw, code)
			local report = controls.profiler(raw, code)
			if visible() then
				available, powered = false, report.powered
				paired, connected = report.devices, {}
				message("Read-only view · Manage devices in Settings")
				render()
			elseif not detailed then
				powered = report.powered
				render()
			end
			finish()
		end)
	end
	if not detailed then
		exec(power_command, function(raw, code)
			local value = controls.power(raw, code)
			if value == nil then
				fallback()
				return
			end
			powered = value
			render()
			finish()
		end)
		return
	end
	exec(assert(controls.command("power")) .. " 2>/dev/null", function(raw, code)
		local power = controls.power(raw, code)
		if power == nil then
			fallback()
			return
		end
		if not power then
			if visible() then
				powered, available, paired, connected = false, true, {}, {}
				render()
			end
			finish()
			return
		end
		exec(assert(controls.command("paired")) .. " 2>/dev/null", function(list, result)
			local remembered = controls.devices(list, result)
			if not remembered then
				fallback()
				return
			end
			exec(assert(controls.command("connected")) .. " 2>/dev/null", function(devices, exit)
				local live = controls.devices(devices, exit)
				if not live then
					fallback()
					return
				end
				if visible() then
					powered, available, paired, connected = power, true, remembered, live
					render()
				end
				finish()
			end)
		end)
	end)
end

power_button:subscribe("mouse.clicked", function()
	if powered == nil then
		return
	end
	local desired = not powered
	local token = begin_action("power", nil, "Changing power…")
	if not token then
		return
	end
	local function apply()
		exec_action(token, assert(controls.command("power")), function(raw, code)
			if controls.power(raw, code) == nil then
				finish_action(token, "Power status unavailable; no changes made", true)
				return
			end
			current_action.phase = "executing"
			exec_action(token, assert(controls.command("power", desired)), function(_, exit)
				if exit ~= 0 then
					finish_action(token, "Power change failed · Use Settings", true)
					return
				end
				current_action.phase = "readback"
				exec_action(token, assert(controls.command("power")), function(value, result)
					local verified = controls.power(value, result) == desired
					if verified then
						powered = desired
					end
					finish_action(
						token,
						verified and "Bluetooth power updated" or "Power change could not be verified",
						not verified
					)
				end)
			end)
		end)
	end
	if desired then
		apply()
	else
		confirm(
			token,
			"Turn off Bluetooth? Connected keyboards, mice and other accessories will disconnect.",
			"Turn off",
			apply
		)
	end
end)
scan_button:subscribe("mouse.clicked", function()
	if not opened or not available or not powered or current_action then
		return
	end
	if scanning and os.time() - scan_started < 65 then
		return
	end
	scan_revision = scan_revision + 1
	local request, view = scan_revision, session
	scanning, scanned, scan_started = true, false, os.time()
	message("Scanning nearby · Put your accessory in pairing mode")
	render()
	sbar.exec(assert(controls.command("inquiry")) .. " 2>/dev/null", function(raw, code)
		if request ~= scan_revision or view ~= session or not opened then
			return
		end
		scanning, scanned = false, true
		local devices = controls.devices(raw, code)
		nearby = devices or {}
		message(devices and "Scan complete" or "Scan failed · Check Bluetooth permissions", devices == nil)
		render()
	end)
end)
for group, rows in pairs(slots) do
	for _, slot in ipairs(rows) do
		slot.button:subscribe("mouse.clicked", function()
			local device = slot.device
			if not device or current_action or scanning then
				return
			end
			if group == "nearby" or slot.system_managed then
				details:close()
				sbar.exec(settings.commands.bluetooth)
			else
				device_action(device, group == "connected" and "disconnect" or "connect")
			end
		end)
		slot.forget:subscribe("mouse.clicked", function()
			if group ~= "nearby" and slot.device and not slot.system_managed then
				device_action(slot.device, "unpair")
			end
		end)
	end
end
refresh_button:subscribe("mouse.clicked", function()
	if not current_action and not scanning then
		refresh()
	end
end)
settings_button:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.bluetooth)
end)
audio_button:subscribe("mouse.clicked", function()
	details:close()
	popup.toggle("widgets.volume")
end)
bluetooth:subscribe({ "routine", "forced", "system_woke" }, refresh)
timer:subscribe("routine", function()
	if not opened then
		return
	end
	local now = os.time()
	if scanning and now - scan_started >= 65 then
		scanning, scan_revision = false, scan_revision + 1
		message("Scan timed out · Try again", true)
	end
	if current_action and now - current_action.started >= 65 then
		current_action, action_revision = nil, action_revision + 1
		message("Bluetooth action timed out · Refresh before retrying", true)
	end
	render()
	if not current_action and not scanning then
		refresh()
	end
end)
details = popup.bind(bluetooth, {
	settings_command = settings.commands.bluetooth,
	on_open = function()
		opened, session = true, session + 1
		for _, style in ipairs(styles) do
			style:reset()
		end
		message_item:set({ drawing = false })
		timer:set({ update_freq = 10 })
		render()
		refresh()
		local view = session
		sbar.exec(profiler_command, function(raw, code)
			if opened and view == session then
				batteries = controls.profiler(raw, code).devices
				render()
			end
		end)
	end,
	on_close = function()
		opened, session = false, session + 1
		scanning, scanned, nearby = false, false, {}
		scan_revision = scan_revision + 1
		if current_action and current_action.phase == "preflight" and not current_action.allow_closed then
			current_action, action_revision = nil, action_revision + 1
		end
		timer:set({ update_freq = 0 })
		for _, style in ipairs(styles) do
			style:reset()
		end
	end,
})
render()
refresh()
return bluetooth
