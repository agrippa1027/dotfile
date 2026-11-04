return {
	paddings = 5,
	group_paddings = 5,
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
		small_group_edge_padding = 18,
	},
	bar = {
		height = 38,
		-- Match yabai's 10-point side padding without extra outer content spacing.
		margin = 10,
		y_offset = 5,
		padding_left = 0,
		padding_right = 0,
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
