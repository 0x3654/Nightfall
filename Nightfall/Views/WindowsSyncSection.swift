import SwiftUI

/// Секция настроек «Sync Windows theme»: список найденных Parallels VM,
/// выбор (направляет список VM через запятую в WindowsVMName), Setup/Remove
/// обвязки в каждой VM и статусы.
struct WindowsSyncSection: View {
	@ObservedObject private var windowsVMName =
		ObservableUserDefault<String>(UserDefaults.Keys.windowsVMName)

	@State private var vms: [ParallelsVM] = []
	@State private var statuses: [String: Status] = [:]
	@State private var loading = false

	enum Status: Equatable {
		case unknown
		case working
		case ready
		case failed(String)

		var label: String {
			switch self {
			case .unknown: return ""
			case .working: return "setting up…"
			case .ready: return "✓ ready"
			case .failed: return "failed"
			}
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				Text("Detected VMs")
					.font(.system(size: 10, weight: .semibold))
				Spacer()
				if loading {
					Text("…").font(.system(size: 10))
				} else {
					Button(action: refresh) {
						Text("↻")
					}
					.buttonStyle(BorderlessButtonStyle())
					.cursor(.pointingHand)
				}
			}

			if vms.isEmpty && !loading {
				Text(loading ? "" : "No VMs found")
					.font(.system(size: 10))
					.foregroundColor(.secondary)
			}

			ForEach(vms) { vm in
				vmRow(vm)
			}

			TextField("VMs, comma-separated", text: $windowsVMName.value)
				.textFieldStyle(.roundedBorder)
				.font(.system(size: 11))
		}
		.onAppear(perform: refresh)
	}

	private func vmRow(_ vm: ParallelsVM) -> some View {
		let status = statuses[vm.name] ?? .unknown
		return HStack(spacing: 4) {
			if vm.isWindows {
				Toggle(vm.name, isOn: Binding(
					get: { selected.contains(vm.name) },
					set: { onSelect(vm, $0) }
				))
				.font(.system(size: 11))
			} else {
				Text(vm.name).font(.system(size: 11)).foregroundColor(.secondary)
				Text("(not Windows)").font(.system(size: 9)).foregroundColor(.secondary)
			}

			Spacer(minLength: 4)

			if !vm.isRunning {
				Text(vm.state)
					.font(.system(size: 9))
					.foregroundColor(.orange)
			}

			if vm.isWindows {
				Button("Setup") { provision(vm) }
					.buttonStyle(BorderlessButtonStyle())
					.font(.system(size: 10))
					.cursor(.pointingHand)
					.disabled(status == .working || !vm.isRunning)

				Text(status.label)
					.font(.system(size: 9))
					.foregroundColor(
						status == .ready ? .green : (status == .failed("") ? .red : .secondary))
			}
		}
	}

	// MARK: - Действия

	private var selected: [String] {
		UserDefaults.standard.windowsVMNames
	}

	private func onSelect(_ vm: ParallelsVM, _ on: Bool) {
		var set = Set(selected)
		if on { set.insert(vm.name) } else { set.remove(vm.name) }
		windowsVMName.value = set.sorted().joined(separator: ", ")
	}

	private func refresh() {
		loading = true
		DispatchQueue.global(qos: .userInitiated).async {
			let list = WindowsVMProvisioner.listVMs()
			var checks: [String: Status] = [:]
			for vm in list where vm.isWindows && vm.isRunning {
				checks[vm.name] =
					WindowsVMProvisioner.isProvisioned(vm.name) ? .ready : .unknown
			}
			DispatchQueue.main.async {
				vms = list
				statuses.merge(checks) { _, new in new }
				loading = false
			}
		}
	}

	private func provision(_ vm: ParallelsVM) {
		statuses[vm.name] = .working
		WindowsVMProvisioner.setup(vm.name) { result in
			DispatchQueue.main.async {
				switch result {
				case .success:
					statuses[vm.name] = .ready
					// сразу применить текущую тему к свеженастроенной VM
					WindowsThemeSync.push(dark: getAppearanceTheme() == .dark)
				case .failure(let error):
					statuses[vm.name] = .failed(error.localizedDescription)
				}
			}
		}
	}
}

#if DEBUG
	struct WindowsSyncSectionPreview: PreviewProvider {
		static var previews: some View {
			WindowsSyncSection().frame(width: 240)
		}
	}
#endif
