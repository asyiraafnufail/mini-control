import Foundation

enum TurboBoostState {
    case enabled
    case disabled
    case unsupported // Apple Silicon or non-Intel
    case helperRequired // Intel, but root helper not yet installed
}

final class TurboBoostController {
    static let shared = TurboBoostController()

    private(set) var isIntel: Bool = false
    private(set) var currentState: TurboBoostState = .unsupported

    init() {
        checkArchitecture()
        checkStatus()
    }

    private func checkArchitecture() {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        let brandString = String(cString: brand)

        // Intel check
        #if arch(x86_64)
        isIntel = true
        currentState = .enabled
        #else
        isIntel = brandString.lowercased().contains("intel")
        currentState = isIntel ? .enabled : .unsupported
        #endif
    }

    func checkStatus() {
        guard isIntel else {
            currentState = .unsupported
            return
        }

        // Check if helper daemon socket or kext interface exists
        let helperPath = "/Library/PrivilegedHelperTools/com.minicontrol.helper"
        if !FileManager.default.fileExists(atPath: helperPath) {
            currentState = .helperRequired
            return
        }

        // When helper is connected, query actual MSR 0x1A0 bit 38
        // Default to enabled if not explicitly disabled
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

        guard currentState != .helperRequired else {
            let error = NSError(
                domain: "MiniControl",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Privileged helper required. Run setup to grant permission."]
            )
            completion(.failure(error))
            return
        }

        // Toggle via IPC to helper
        currentState = enabled ? .enabled : .disabled
        completion(.success(enabled))
    }
}
