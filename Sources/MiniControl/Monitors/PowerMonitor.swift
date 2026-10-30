import Foundation
import IOKit.ps
import IOKit

struct PowerStatus {
    let isACConnected: Bool
    let isCharging: Bool
    let batteryPercent: Int
    let adapterWatts: Int?
    let instantaneousWatts: Double // Positive = charging rate, Negative = discharging rate

    var formattedWatts: String {
        if isCharging {
            return String(format: "+%.1fW", instantaneousWatts)
        } else if isACConnected {
            return "0.0W"
        } else {
            return String(format: "%.1fW", instantaneousWatts)
        }
    }

    var menuSummary: String {
        if isCharging {
            let adapterStr = adapterWatts != nil ? " (Adapter: \(adapterWatts!)W)" : ""
            return String(format: "Charging: +%.1fW%@", instantaneousWatts, adapterStr)
        } else if isACConnected {
            let adapterStr = adapterWatts != nil ? " (\(adapterWatts!)W)" : ""
            return "Power: AC Connected\(adapterStr)"
        } else {
            return String(format: "Discharging: %.1fW (%d%%)", abs(instantaneousWatts), batteryPercent)
        }
    }
}

final class PowerMonitor {
    typealias Handler = (PowerStatus) -> Void

    private var runLoopSource: CFRunLoopSource?
    var onUpdate: Handler?
    private(set) var currentStatus: PowerStatus?

    init() {
        registerForNotifications()
        refresh()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }

    func refresh() {
        let status = readStatus()
        self.currentStatus = status
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(status)
        }
    }

    private func registerForNotifications() {
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.refresh()
        }, context).takeRetainedValue()

        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
    }

    private func readStatus() -> PowerStatus {
        var isAC = false
        var isCharging = false
        var percent = 100
        var adapterWatts: Int? = nil
        var instantWatts: Double = 0.0

        // 1. Check IOPS for generic state
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
                for ps in list {
                    if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                        if let state = desc[kIOPSPowerSourceStateKey] as? String {
                            isAC = (state == kIOPSACPowerValue)
                        }
                        if let charging = desc[kIOPSIsChargingKey] as? Bool {
                            isCharging = charging
                        }
                        if let cur = desc[kIOPSCurrentCapacityKey] as? Int,
                           let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                            percent = Int((Double(cur) / Double(max)) * 100.0)
                        }
                    }
                }
            }
        }

        // 2. Query AppleSmartBattery in IORegistry for exact Amperage, Voltage, and AdapterDetails
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != MACH_PORT_NULL {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any] {

                let voltageMV = dict["Voltage"] as? Double ?? 0.0     // Millivolts
                let amperageMA = dict["Amperage"] as? Double ?? 0.0    // Milliamps (can be negative)

                // Power in Watts = (V * A) / 1,000,000
                instantWatts = (voltageMV * amperageMA) / 1_000_000.0

                if let adapter = dict["AdapterDetails"] as? [String: Any] {
                    adapterWatts = adapter["Watts"] as? Int
                }

                if let charging = dict["IsCharging"] as? Bool {
                    isCharging = charging
                }
                if let externalConnected = dict["ExternalConnected"] as? Bool {
                    isAC = externalConnected
                }
            }
            IOObjectRelease(service)
        }

        return PowerStatus(
            isACConnected: isAC,
            isCharging: isCharging,
            batteryPercent: percent,
            adapterWatts: adapterWatts,
            instantaneousWatts: instantWatts
        )
    }
}
