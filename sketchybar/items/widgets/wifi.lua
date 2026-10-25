local sbar = require("sketchybar")
-- Popup layout adapted from FelixKratz/dotfiles (GPL-3.0); see vendor/README.md.
local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local network = require("lib.network")
local popup = require("lib.popup")
local utils = require("lib.utils")

local wifi = sbar.add("item", "widgets.wifi", {
	position = "right",
	update_freq = 30,
	icon = { string = icons.wifi.disconnected, color = colors.grey },
	label = { drawing = false },
	background = { color = colors.transparent },
	popup = { align = "center", height = settings.popup.height },
})

local popup_width = settings.popup.width
local heading = sbar.add("item", "widgets.wifi.heading", {
	position = "popup." .. wifi.name,
	width = popup_width,
	align = "center",
	icon = { string = icons.wifi.router },
	label = { string = "Wi-Fi", font = { style = settings.font.style_map.Bold } },
})

local rows = {}
for _, entry in ipairs({
	{ "connection", "Connection:" },
	{ "ssid", "Network:" },
	{ "ip", "IP address:" },
	{ "router", "Router:" },
	{ "interface", "Interface:" },
}) do
	rows[entry[1]] = sbar.add("item", "widgets.wifi." .. entry[1], {
		position = "popup." .. wifi.name,
		width = popup_width,
		icon = { string = entry[2], font = { family = settings.font.icon }, width = 100, align = "left" },
		label = { string = "Checking…", max_chars = 24, width = popup_width - 100, align = "right" },
	})
end

local open_settings = sbar.add("item", "widgets.wifi.settings", {
	position = "popup." .. wifi.name,
	width = popup_width,
	align = "center",
	icon = { drawing = false },
	label = { string = "Open Wi-Fi Settings", color = colors.blue },
})

local labels = {
	connected = "Connected",
	connecting = "Connecting…",
	disconnected = "Disconnected",
	off = "Radio off",
	unavailable = "Unavailable",
}

local function render(status, show_details)
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
	heading:set({ label = status.ssid or "Wi-Fi" })
	rows.connection:set({ label = labels[status.state] })
	rows.ssid:set({ label = status.ssid or (connected and "Hidden by macOS" or "—") })
	rows.ip:set({ label = status.ip or "—" })
	rows.router:set({ label = status.router or "—" })
	rows.interface:set({ label = status.interface or "—" })
end

local interface
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
	local show_details = wifi:query().popup.drawing == "on"

	local function exec(command, callback)
		started_at = os.time()
		sbar.exec(command .. " 2>/dev/null", function(result)
			if request == generation then
				callback(utils.trim(result))
			end
		end)
	end

	local function finish(data)
		render(network.parse(data), show_details and wifi:query().popup.drawing == "on")
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
local details = popup.bind(wifi, { on_open = refresh })
open_settings:subscribe("mouse.clicked", function()
	details:close()
	sbar.exec(settings.commands.wifi)
end)

refresh()
return wifi
