import Foundation

/// Проталкивает текущую тему macOS в Windows-VM (Parallels). Fire-and-forget:
/// каждая VM запускается отдельным Process'ом (параллельно), выключенная или
/// спящая VM тихо пропускается, остальные живут.
///
/// Обвязка на стороне Windows (задача планировщика MacThemeSync от залогиненного
/// пользователя + скрипты в C:\Users\Public) разворачивается отдельно —
/// `prlctl exec` сам по себе работает от SYSTEM и тему пользовательской сессии
/// менять не может.
enum WindowsThemeSync {
	/// Дедупликация: переключение из Nightfall даёт два события
	/// (прямой вызов + AppleInterfaceThemeChangedNotification).
	private static var lastPush: (dark: Bool, at: Date)?

	/// Протолкнуть тему: `dark: true` — тёмная.
	static func push(dark: Bool) {
		let defaults = UserDefaults.standard
		guard defaults.syncWindowsVM else { return }

		// Та же тема уже пушена меньше 2 секунд назад — пропускаем
		let now = Date()
		if let last = lastPush, last.dark == dark, now.timeIntervalSince(last.at) < 2 {
			return
		}
		lastPush = (dark, now)

		let mode = dark ? "dark" : "light"
		let cmd = "Set-Content C:\\Users\\Public\\mac_theme.txt '\(mode)'; schtasks /Run /TN MacThemeSync"

		for vm in defaults.windowsVMNames {
			let task = Process()
			task.executableURL = URL(fileURLWithPath: "/usr/local/bin/prlctl")
			task.arguments = ["exec", vm, "powershell", "-NoProfile", "-Command", cmd]
			task.standardOutput = FileHandle.nullDevice
			task.standardError = FileHandle.nullDevice
			try? task.run()  // не ждём завершения
		}
	}
}
