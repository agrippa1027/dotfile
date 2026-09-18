return {
	paddings = 5,
	group_paddings = 5,
	icons = "NedFont",
	font = {
		icon = "Hack Nerd Font",
		text = "Comic Code Ligatures",
		style_map = {
			Regular = "Regular",
			Semibold = "Regular",
			Bold = "Bold",
			Heavy = "Bold",
			Black = "Bold",
		},
	},
	corner_radius = 8,
	bar = {
		height = 38,
		margin = 8,
		y_offset = 5,
		padding_left = 8,
		padding_right = 8,
	},
	popup = {
		close_delay = 0.15,
		apple_height = 32,
		wifi_height = 30,
		wifi_width = 280,
		volume_width = 250,
	},
	commands = {
		settings = "open -a 'System Settings'",
		activity = "open -a 'Activity Monitor'",
		bluetooth = "open 'x-apple.systempreferences:com.apple.BluetoothSettings'",
		battery = "open 'x-apple.systempreferences:com.apple.Battery-Settings.extension'",
		sound = "open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'",
		wifi = "/usr/bin/open 'x-apple.systempreferences:com.apple.wifi-settings-extension'",
	},
}
