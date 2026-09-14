import Foundation

struct ParallelsVM: Identifiable, Equatable {
	let name: String
	let state: String  // "running" / "stopped" / "suspended" / …
	let os: String  // "win-11", "kali", …

	var isWindows: Bool { os.hasPrefix("win") }
	var isRunning: Bool { state == "running" }
	var id: String { name }
}

enum ProvisionError: LocalizedError {
	case vmUnreachable(String)
	case transferFailed
	case commandFailed(String)

	var errorDescription: String? {
		switch self {
		case .vmUnreachable(let detail):
			return "VM is not reachable (running? Parallels Tools?). \(detail)"
		case .transferFailed:
			return "Script transfer to the VM failed"
		case .commandFailed(let detail):
			return detail.isEmpty ? "Command in the VM failed" : detail
		}
	}
}

/// Разворачивает и снимает обвязку синка темы в Windows-VM (Parallels):
/// `MacThemeSync.ps1` + `.vbs` в `C:\Users\Public` и задачу планировщика
/// от залогиненного пользователя. Идемпотентно — повторный setup безопасен.
///
/// Почему это нужно: `prlctl exec` работает от SYSTEM и не может менять тему
/// пользовательской сессии; задача планировщика — единственный легальный мостик.
/// Механика обкатана прототипом (см. vm/ в репозитории проекта).
enum WindowsVMProvisioner {

	/// Содержимое MacThemeSync.ps1: читает флаг от мака и перекрашивает тему
	/// (+ broadcast, чтобы таскбар и приложения перерисовались сразу).
	private static let syncScript = #"""
		$mode = Get-Content 'C:\Users\Public\mac_theme.txt' -ErrorAction SilentlyContinue
		$v = if ($mode -match 'dark') { 0 } else { 1 }
		$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
		New-Item -Path $k -Force | Out-Null
		Set-ItemProperty -Path $k -Name AppsUseLightTheme -Value $v -Type DWord
		Set-ItemProperty -Path $k -Name SystemUsesLightTheme -Value $v -Type DWord
		$sig = '[DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);'
		$t = Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace Win32 -PassThru
		$r = [IntPtr]::Zero
		[void]$t::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$r)
		"""#

	/// VBS-обёртка: скрытый запуск, чтобы PowerShell не мигал окном при каждом переключении.
	private static let vbsScript = #"""
		CreateObject("Wscript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\MacThemeSync.ps1", 0, False
		"""#

	// MARK: - Список VM

	/// `prlctl list -a -i` → [VM]. Пустой массив = Parallels не найден.
	static func listVMs() -> [ParallelsVM] {
		let output = prlctl(["list", "-a", "-i"]).out
		var vms: [ParallelsVM] = []
		var name: String?, state: String?, os: String?

		func flush() {
			if let name = name {
				vms.append(ParallelsVM(name: name, state: state ?? "", os: os ?? ""))
			}
			name = nil; state = nil; os = nil
		}

		for line in output.components(separatedBy: .newlines) {
			if let v = field("Name", line) { flush(); name = v }
			if let v = field("State", line) { state = v }
			if let v = field("OS", line) { os = v }
		}
		flush()
		return vms
	}

	/// Задача MacThemeSync уже развернута в VM?
	static func isProvisioned(_ vm: String) -> Bool {
		let out = guest(vm, "[bool](Get-ScheduledTask MacThemeSync -ErrorAction SilentlyContinue)").out
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return out.lowercased().contains("true")
	}

	// MARK: - Setup / Remove

	static func setup(_ vm: String, completion: @escaping (Result<Void, ProvisionError>) -> Void) {
		runInBackground {
			completion(Self.setup(vm))
		}
	}

	static func remove(_ vm: String, completion: @escaping (Result<Void, ProvisionError>) -> Void) {
		runInBackground {
			completion(Self.remove(vm))
		}
	}

	// MARK: - Реализация (синхронная, в фоне)

	private static func setup(_ vm: String) -> Result<Void, ProvisionError> {
		// VM отвечает?
		let probe = guest(vm, "Write-Output ok")
		guard probe.out.contains("ok") else {
			return .failure(.vmUnreachable(probe.out.trimmingCharacters(in: .whitespacesAndNewlines)))
		}

		do {
			try transfer(syncScript, to: vm, at: "C:\\Users\\Public\\MacThemeSync.ps1")
			try transfer(vbsScript, to: vm, at: "C:\\Users\\Public\\MacThemeSync.vbs")
		} catch let error as ProvisionError {
			return .failure(error)
		} catch {
			return .failure(.transferFailed)
		}

		// Задача планировщика от залогиненного пользователя (не SYSTEM!)
		let user = guest(vm, "(Get-CimInstance Win32_ComputerSystem).UserName")
			.out.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !user.isEmpty, !user.lowercased().contains("exception") else {
			return .failure(.commandFailed("No logged-in user detected in the VM"))
		}
		let create = guest(
			vm,
			"schtasks.exe /Create /F /TN MacThemeSync /TR 'wscript.exe C:\\Users\\Public\\MacThemeSync.vbs'"
				+ " /SC ONCE /ST 23:59 /RU '\(user)' /IT")
		guard create.out.contains("SUCCESS") else {
			return .failure(.commandFailed(create.out.trimmingCharacters(in: .whitespacesAndNewlines)))
		}

		// Убрать триггер-заглушку 23:59 — задача чисто ручная (только /Run)
		_ = guest(vm, "$t=Get-ScheduledTask MacThemeSync; $t.Triggers=@(); Set-ScheduledTask -InputObject $t | Out-Null")

		return isProvisioned(vm) ? .success(()) : .failure(.commandFailed("Task verification failed"))
	}

	private static func remove(_ vm: String) -> Result<Void, ProvisionError> {
		let probe = guest(vm, "Write-Output ok")
		guard probe.out.contains("ok") else {
			return .failure(.vmUnreachable(probe.out.trimmingCharacters(in: .whitespacesAndNewlines)))
		}
		_ = guest(vm, "schtasks.exe /Delete /F /TN MacThemeSync")  // "нет такой" — не ошибка
		_ = guest(vm, "Remove-Item 'C:\\Users\\Public\\MacThemeSync.ps1',"
			+ " 'C:\\Users\\Public\\MacThemeSync.vbs', 'C:\\Users\\Public\\mac_theme.txt'"
			+ " -ErrorAction SilentlyContinue")
		return .success(())
	}

	// MARK: - Передача скрипта в VM

	/// base64 → кусками по 700 символов (у prlctl exec лимит длины команды ~4–5 КБ)
	/// с проверкой длины на приёме — куски умеют теряться.
	private static func transfer(_ content: String, to vm: String, at path: String) throws {
		let b64 = Data(content.utf8).base64EncodedString()
		let temp = "C:\\Users\\Public\\nightfall_transfer.b64"

		let chars = Array(b64)
		var offset = 0
		var index = 0
		while offset < chars.count {
			let chunk = String(chars[offset..<min(offset + 700, chars.count)])
			let command = index == 0
				? "Set-Content \(temp) '\(chunk)'"
				: "Add-Content \(temp) '\(chunk)'"
			let result = guest(vm, command)
			if result.code != 0 && !result.out.isEmpty {
				throw ProvisionError.commandFailed("chunk \(index): " + result.out)
			}
			if result.code != 0 {
				throw ProvisionError.transferFailed
			}
			offset += 700
			index += 1
		}

		// Длина на приёме совпадает?
		let echo = guest(vm, "(([IO.File]::ReadAllText('\(temp)')) -replace '\\s','').Length")
			.out.trimmingCharacters(in: .whitespacesAndNewlines)
		guard Int(echo) == b64.count else {
			throw ProvisionError.transferFailed
		}

		let decode = guest(
			vm,
			"$d=[IO.File]::ReadAllText('\(temp)') -replace '\\s','';"
				+ " [IO.File]::WriteAllText('\(path)', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($d)))")
		guard decode.code == 0 else {
			throw ProvisionError.commandFailed(decode.out.trimmingCharacters(in: .whitespacesAndNewlines))
		}
		_ = guest(vm, "Remove-Item '\(temp)' -ErrorAction SilentlyContinue")
	}

	// MARK: - Процессы

	private static func guest(_ vm: String, _ command: String) -> (code: Int32, out: String) {
		prlctl(["exec", vm, "powershell", "-NoProfile", "-Command", command])
	}

	private static func prlctl(_ arguments: [String]) -> (code: Int32, out: String) {
		let task = Process()
		task.executableURL = URL(fileURLWithPath: "/usr/local/bin/prlctl")
		task.arguments = arguments
		let pipe = Pipe()
		task.standardOutput = pipe
		task.standardError = pipe
		guard (try? task.run()) != nil else { return (-1, "") }
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		task.waitUntilExit()
		return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
	}

	private static func runInBackground(_ work: @escaping () -> Void) {
		DispatchQueue.global(qos: .userInitiated).async(execute: work)
	}

	private static func field(_ name: String, _ line: String) -> String? {
		guard line.hasPrefix(name + ":") else { return nil }
		return line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
	}
}
