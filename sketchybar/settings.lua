return {
	paddings = 5,

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
	workspaces = {
		width = 20,
		gap = 1,
	},
	bar = {
		height = 26,
		margin = 0,
		y_offset = 0,
		blur_radius = 20,
		padding_left = 8,
		padding_right = 8,
	},
	popup = {
		apple_height = 32,
		height = 30,
		width = 320,
		network_width = 350,
		padding = 14,
		gap = 6,
		corner_radius = 4,
		border_width = 2,
		control_height = 26,
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
