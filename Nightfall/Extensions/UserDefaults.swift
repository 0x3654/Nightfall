import Foundation

extension UserDefaults {
	struct Keys {
		static let useTransition = "UseTransition"
		static let startAtLogin = "StartAtLogin"
		static let syncWindowsVM = "SyncWindowsVM"
		static let windowsVMName = "WindowsVMName"
	}

	var useTransition: Bool {
		get { self.bool(forKey: Keys.useTransition) }
		set { self.set(newValue, forKey: Keys.useTransition) }
	}

	var startAtLogin: Bool {
		get { self.bool(forKey: Keys.startAtLogin) }
		set { self.set(newValue, forKey: Keys.startAtLogin) }
	}

	var syncWindowsVM: Bool {
		get { self.bool(forKey: Keys.syncWindowsVM) }
		set { self.set(newValue, forKey: Keys.syncWindowsVM) }
	}

	/// Список VM Parallels через запятую (например "Windows 11, WinRU").
	var windowsVMNames: [String] {
		get {
			(self.string(forKey: Keys.windowsVMName) ?? "Windows 11")
				.split(whereSeparator: { $0 == "," || $0 == ";" })
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty }
		}
	}
}
