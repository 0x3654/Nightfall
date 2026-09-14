import Cocoa

/// Toggles the system between light and dark modes, using a transition animation if available.
func toggleDarkMode() {
	let defaults = UserDefaults.standard

	let transition: NSGlobalPreferenceTransition?
	if defaults.useTransition && PermissionUtil.checkScreenCapturePermission(canPrompt: true) {
		transition =
			NSGlobalPreferenceTransition.transition() as! NSGlobalPreferenceTransition?
	} else {
		transition = nil
	}

	// If the transition is disabled, the second argument must be true or nothing happens
	let target = !getAppearanceTheme()
	setAppearanceTheme(to: target, notify: transition == nil)

	// Протолкнуть новую тему в Windows-VM (Parallels), если синк включён
	WindowsThemeSync.push(dark: target == .dark)

	transition?.postChangeNotification(0) {}
}
