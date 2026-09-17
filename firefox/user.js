// Allow Firefox to load chrome/userChrome.css at startup.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Match the static Hubbamax chrome theme.
user_pref("browser.theme.toolbar-theme", 0);
user_pref("browser.theme.content-theme", 0);

// Enable macOS memory-pressure handling and inactive tab unloading.
user_pref("browser.tabs.unloadOnLowMemory", true);
user_pref("browser.lowMemoryResponseMask", 3);
user_pref("browser.tabs.unloadTabInContextMenu", true);
