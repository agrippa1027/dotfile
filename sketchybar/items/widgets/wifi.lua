local sbar = require("sketchybar")
-- Popup layout adapted from FelixKratz/dotfiles (GPL-3.0); see vendor/README.md.
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local network = require("lib.network")
local popup = require("lib.popup")
local utils = require("lib.utils")
local ui = require("lib.panel")
local interface, cached_status, panel

local wifi = sbar.add("item", "widgets.wifi", {
	position = "right",
	update_freq = 30,
	icon = { string = icons.wifi.disconnected, color = colors.grey },
	label = { drawing = false },
	background = { color = colors.transparent },
	popup = { align = "right", height = settings.popup.height },
})

local popup_width = settings.popup.network_width
local heading = sbar.add("item", "widgets.wifi.heading", {
	position = "popup." .. wifi.name,
	width = popup_width,
	cell_span = 4,
	align = "left",
	background = { padding_left = 0, padding_right = 0 },
	icon = {
		string = icons.wifi.connected,
		color = colors.accent,
		font = { size = 24 },
		padding_left = 0,
		padding_right = 14,
	},
	label = { string = "Wi-Fi", max_chars = 28, font = { style = settings.font.style_map.Bold, size = 14 } },
})

ui.heading(heading)

local rows = {}
local function detail_row(name, caption, visible)
	rows[name] = sbar.add("item", "widgets.wifi." .. name, {
		position = "popup." .. wifi.name,
		width = popup_width,
		cell_span = 4,
		drawing = visible or false,
		background = { height = 26, padding_left = 0, padding_right = 0 },
		icon = {
			string = caption,
			color = colors.grey,
			font = { family = settings.font.text, size = 12 },
			width = 106,
			align = "left",
			padding_left = 0,
		},
		label = {
			string = "Checking…",
			max_chars = 24,
			width = popup_width - 136,
			align = "right",
			font = { size = 12 },
		},
	})
	return rows[name]
end
detail_row("connection", "STATUS", true)
rows.connection:set({ icon = { font = { size = 10 } }, label = { font = { size = 10 } } })

local labels = {
	connected = "Connected",
	connecting = "Connecting…",
	disconnected = "Disconnected",
	off = "Radio off",
	unavailable = "Unavailable",
}

local function render(status, show_details)
	cached_status = status
	local connected = status.state == "connected"
	wifi:set({
		icon = {
			string = connected and icons.wifi.connected or icons.wifi.disconnected,
			color = connected and colors.white or (status.state == "connecting" and colors.orange or colors.grey),
		},
	})
	if not show_details then
		return
	end
	if panel then
		panel:status(status)
	end
	heading:set({
		label = status.ssid or "Wi-Fi",
		icon = {
			string = connected and icons.wifi.connected or icons.wifi.disconnected,
			color = connected and colors.accent or colors.grey,
		},
	})
	rows.connection:set({
		label = {
			string = labels[status.state],
			color = connected and colors.accent or (status.state == "connecting" and colors.orange or colors.grey),
		},
	})
	rows.ssid:set({ label = status.ssid or (connected and "Hidden by macOS" or "—") })
	rows.ip:set({ label = status.ip or "—" })
	rows.router:set({ label = status.router or "—" })
	rows.interface:set({ label = status.interface or "—" })
end

local started_at
local generation = 0
local pending = false
local function refresh()
	local now = os.time()
	-- Allow the native per-command 60s timeout before recovering on an event/routine.
	if started_at and now - started_at < 65 then
		pending = true
		return
	end
	generation = generation + 1
	local request = generation
	started_at = now
	pending = false
	local show_details = popup.is_open(wifi)

	local function exec(command, callback)
		started_at = os.time()
		sbar.exec(command .. " 2>/dev/null", function(result)
			if request == generation then
				callback(utils.trim(result))
			end
		end)
	end

	local function finish(data)
		render(network.parse(data), show_details and popup.is_open(wifi))
		started_at = nil
		if pending then
			refresh()
		end
	end

	local function read_status()
		if not interface then
			finish({})
			return
		end
		local data = { interface = interface }
		local device = utils.quote(interface)
		local function read_ip()
			if network.parse(data).state ~= "connecting" then
				finish(data)
				return
			end
			exec("/usr/sbin/ipconfig getifaddr " .. device, function(result)
				data.ip = result
				finish(data)
			end)
		end
		local function read_link()
			exec("/sbin/ifconfig " .. device, function(result)
				data.link = result
				read_ip()
			end)
		end

		if not show_details then
			read_link()
			return
		end
		exec("/usr/sbin/networksetup -getairportpower " .. device, function(result)
			data.power = result
			if network.parse(data).state == "off" then
				finish(data)
				return
			end
			exec("/usr/sbin/ipconfig getsummary " .. device, function(summary)
				data.summary = summary
				if summary:match("LinkStatusActive%s*:%s*%u+") then
					read_ip()
				else
					read_link()
				end
			end)
		end)
	end
	if interface then
		read_status()
	else
		exec("/usr/sbin/networksetup -listallhardwareports", function(result)
			interface = network.interface(result)
			read_status()
		end)
	end
end

wifi:subscribe({ "routine", "forced", "system_woke", "wifi_change" }, refresh)
panel = require("items.widgets.network_panel").attach(wifi, {
	get_interface = function()
		return interface
	end,
	get_status = function()
		return cached_status
	end,
	refresh = refresh,
	add_details = function()
		return {
			detail_row("ssid", "Network"),
			detail_row("ip", "IP address"),
			detail_row("router", "Gateway"),
			detail_row("interface", "Interface"),
		}
	end,
})
local refresh_item = sbar.add("item", "widgets.wifi.refresh", {
	position = "popup." .. wifi.name,
	width = (popup_width - settings.popup.gap) / 2,
	cell_span = 2,
	align = "center",
	icon = { drawing = false },
	background = { padding_left = 5, padding_right = 5 },
	label = { string = "Refresh", color = colors.white, font = { size = 11 } },
})
local open_settings = sbar.add("item", "widgets.wifi.settings", {
	position = "popup." .. wifi.name,
	width = (popup_width - settings.popup.gap) / 2,
	cell_span = 2,
	align = "center",
	icon = { drawing = false },
	background = { padding_left = 5, padding_right = 5 },
	label = { string = "Choose network  →", color = colors.white, font = { size = 11 } },
})
local refresh_style = ui.action(refresh_item)
local settings_style = ui.action(open_settings)
local details = popup.bind(wifi, {
	settings_command = settings.commands.wifi,
	on_open = function()
		refresh_style:reset()
		settings_style:reset()
		refresh()
		panel:open()
	end,
	on_close = function()
		panel:close()
	end,
})
refresh_item:subscribe("mouse.clicked", refresh)
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.wifi)
end)

refresh()
return wifi
