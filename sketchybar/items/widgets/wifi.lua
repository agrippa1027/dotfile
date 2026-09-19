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
	popup = { align = "center", height = settings.popup.wifi_height },
})

local popup_width = settings.popup.wifi_width
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

local function render(status)
	local connected = status.state == "connected"
	wifi:set({
		icon = {
			string = connected and icons.wifi.connected or icons.wifi.disconnected,
			color = connected and colors.white or (status.state == "connecting" and colors.orange or colors.grey),
		},
	})
	heading:set({ label = status.ssid or "Wi-Fi" })
	rows.connection:set({ label = labels[status.state] })
	rows.ssid:set({ label = status.ssid or (connected and "Hidden by macOS" or "—") })
	rows.ip:set({ label = status.ip or "—" })
	rows.router:set({ label = status.router or "—" })
	rows.interface:set({ label = status.interface or "—" })
end

local interface
local updating = false
local function refresh()
	if updating then
		return
	end
	updating = true
	local function read_status()
		if not interface then
			render(network.parse({}))
			updating = false
			return
		end
		local data = { interface = interface }
		local remaining = 4
		local device = utils.quote(interface)
		local commands = {
			power = "/usr/sbin/networksetup -getairportpower " .. device,
			summary = "/usr/sbin/ipconfig getsummary " .. device,
			ip = "/usr/sbin/ipconfig getifaddr " .. device,
			link = "/sbin/ifconfig " .. device,
		}
		for key, command in pairs(commands) do
			sbar.exec(command .. " 2>/dev/null", function(result)
				data[key] = utils.trim(result)
				remaining = remaining - 1
				if remaining == 0 then
					render(network.parse(data))
					updating = false
				end
			end)
		end
	end
	if interface then
		read_status()
	else
		sbar.exec("/usr/sbin/networksetup -listallhardwareports", function(result)
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
