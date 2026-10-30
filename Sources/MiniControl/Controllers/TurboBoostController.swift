import Foundation

enum TurboBoostState {
    case enabled
    case disabled
    case unsupported
}

final class TurboBoostController {
    static let shared = TurboBoostController()

    typealias ChangeHandler = (TurboBoostState) -> Void
    var onStateChange: ChangeHandler?

    private(set) var isIntel: Bool = false
    private(set) var currentState: TurboBoostState = .enabled
    private(set) var isHelperInstalled: Bool = false

    private let helperPath = "/usr/local/bin/minicontrol-tb"
    private let stateFile = "/tmp/minicontrol_tb_state"
    private let helperQueue = DispatchQueue(label: "com.minicontrol.helper-queue", qos: .userInitiated)
    private var wakeWorkItem: DispatchWorkItem?

    init() {
        checkArchitecture()
        checkHelperInstalled()

        let intendedEnabled = UserDefaults.standard.object(forKey: "turboBoostEnabled") as? Bool ?? true
        if !intendedEnabled && isHelperInstalled {
            toggle(enabled: false) { _ in }
        } else {
            refreshRealStatus()
        }
    }

    private func checkArchitecture() {
        #if arch(x86_64)
        isIntel = true
        #else
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)
        isIntel = brandString.lowercased().contains("intel")
        #endif

        if !isIntel {
            currentState = .unsupported
        }
    }

    func checkHelperInstalled() {
        isHelperInstalled = FileManager.default.fileExists(atPath: helperPath)
    }

    /// Queries actual hardware/kernel state
    func refreshRealStatus() {
        guard isIntel else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            // 1. Check if DisableTurboBoost kext is currently active in Mach kernel
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/kextstat")
            process.arguments = ["-b", "com.rugarciap.DisableTurboBoost"]
            process.standardOutput = pipe
            process.standardError = Pipe()

            var isKextLoaded = false
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    isKextLoaded = output.contains("com.rugarciap.DisableTurboBoost")
                }
            } catch {
                isKextLoaded = false
            }

            // If kext is loaded into kernel => Turbo Boost is physically DISABLED
            // If kext is NOT loaded => Turbo Boost is physically ENABLED
            let realState: TurboBoostState = isKextLoaded ? .disabled : .enabled

            DispatchQueue.main.async {
                if self.currentState != realState {
                    self.currentState = realState
                    self.onStateChange?(realState)
                }
            }
        }
    }

    /// Re-applies the user's intended Turbo Boost state on wake without user interaction
    func reapplyStateOnWake() {
        guard isIntel else { return }

        // Debounce multiple wake notifications
        wakeWorkItem?.cancel()

        let intendedEnabled = UserDefaults.standard.object(forKey: "turboBoostEnabled") as? Bool ?? true
        if !intendedEnabled {
            let item = DispatchWorkItem { [weak self] in
                self?.toggle(enabled: false) { _ in }
            }
            wakeWorkItem = item
            // Delay 0.5s after wake to ensure CPU cores are fully awake before re-applying MSR
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
        } else {
            refreshRealStatus()
        }
    }

    func toggle(enabled: Bool, completion: @escaping (Result<Bool, Error>) -> Void) {
        guard isIntel else {
            let error = NSError(
                domain: "MiniControl",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Turbo Boost control is only supported on Intel Macs."]
            )
            completion(.failure(error))
            return
        }

        let targetState: TurboBoostState = enabled ? .enabled : .disabled
        self.currentState = targetState

        // Persist user preference across sessions and wake
        UserDefaults.standard.set(enabled, forKey: "turboBoostEnabled")

        // Update state file
        try? (enabled ? "enabled\n" : "disabled\n").write(
            toFile: stateFile,
            atomically: true,
            encoding: .utf8
        )

        if isHelperInstalled {
            helperQueue.async { [weak self] in
                guard let self = self else { return }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-n", self.helperPath, enabled ? "on" : "off"]
                try? process.run()
                process.waitUntilExit()

                // Re-verify actual hardware state after kextload/kextunload
                Thread.sleep(forTimeInterval: 0.3)
                self.refreshRealStatus()

                // Safety retry: If intended to disable but hardware didn't switch (e.g. wake PM lag), retry once
                if !enabled {
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self = self else { return }
                        if self.currentState != .disabled {
                            self.helperQueue.async {
                                let retryProc = Process()
                                retryProc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                                retryProc.arguments = ["-n", self.helperPath, "off"]
                                try? retryProc.run()
                                retryProc.waitUntilExit()
                                Thread.sleep(forTimeInterval: 0.3)
                                self.refreshRealStatus()
                            }
                        }
                    }
                }

                DispatchQueue.main.async {
                    completion(.success(enabled))
                }
            }
        } else {
            // Toggled in user mode
            onStateChange?(currentState)
            completion(.success(enabled))
        }
    }
}
