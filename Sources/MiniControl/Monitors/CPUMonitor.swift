import Foundation
import Darwin

enum CPUStressLevel {
    case normal  // < 50%
    case medium  // 50% - 79%
    case high    // >= 80%

    static func from(usage: Double) -> CPUStressLevel {
        if usage < 50.0 {
            return .normal
        } else if usage < 80.0 {
            return .medium
        } else {
            return .high
        }
    }
}

final class CPUMonitor {
    typealias Handler = (Double, CPUStressLevel) -> Void

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.minicontrol.cpu-monitor", qos: .utility)
    private var prevCpuInfo: processor_info_array_t?
    private var prevNumCpuInfo: mach_msg_type_number_t = 0
    private var numCPUs: natural_t = 0
    private var isRunning = false

    var onUpdate: Handler?
    private(set) var currentUsage: Double = 0.0
    private(set) var currentLevel: CPUStressLevel = .normal

    // CPU Frequency details
    private(set) var baseFrequencyGHz: Double = 0.0
    private(set) var maxTurboFrequencyGHz: Double = 0.0
    private(set) var cpuBrand: String = ""

    init() {
        var mib = [CTL_HW, HW_NCPU]
        var size = MemoryLayout<natural_t>.size
        sysctl(&mib, 2, &numCPUs, &size, nil, 0)

        loadCPUFrequencies()
    }

    deinit {
        stop()
        clearPrevCpuInfo()
    }

    private func loadCPUFrequencies() {
        // 1. Base frequency via sysctl
        var freq: UInt64 = 0
        var freqSize = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency", &freq, &freqSize, nil, 0) == 0 && freq > 0 {
            baseFrequencyGHz = Double(freq) / 1_000_000_000.0
        }

        // 2. Max frequency via sysctl
        var maxFreq: UInt64 = 0
        var maxFreqSize = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency_max", &maxFreq, &maxFreqSize, nil, 0) == 0 && maxFreq > 0 {
            maxTurboFrequencyGHz = Double(maxFreq) / 1_000_000_000.0
        }

        // 3. CPU Brand String
        var brandLen = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &brandLen, nil, 0)
        if brandLen > 0 {
            var brandChars = [CChar](repeating: 0, count: brandLen)
            sysctlbyname("machdep.cpu.brand_string", &brandChars, &brandLen, nil, 0)
            cpuBrand = String(cString: brandChars)
        }

        // 4. Parse Base from Brand String if sysctl gave 0
        if baseFrequencyGHz <= 0, let range = cpuBrand.range(of: "@ ") {
            let sub = cpuBrand[range.upperBound...]
            let numStr = sub.replacingOccurrences(of: "GHz", with: "").trimmingCharacters(in: .whitespaces)
            if let val = Double(numStr) {
                baseFrequencyGHz = val
            }
        }

        // 5. If maxTurboFrequency isn't higher than base, match known Intel Mac profiles
        if maxTurboFrequencyGHz <= baseFrequencyGHz {
            maxTurboFrequencyGHz = resolveTurboMax(brand: cpuBrand, base: baseFrequencyGHz)
        }
    }

    private func resolveTurboMax(brand: String, base: Double) -> Double {
        let b = brand.uppercased()
        if b.contains("9980HK") { return 5.00 }
        if b.contains("9880H")  { return 4.80 }
        if b.contains("9750H")  { return 4.50 }
        if b.contains("8950HK") { return 4.80 }
        if b.contains("8850H")  { return 4.30 }
        if b.contains("8750H")  { return 4.10 }
        if b.contains("1068NG7"){ return 4.10 }
        if b.contains("1038NG7"){ return 3.80 }
        if b.contains("8279U")  { return 4.10 }
        if b.contains("8257U")  { return 3.90 }
        if b.contains("8259U")  { return 3.80 }
        if b.contains("7920HQ") { return 4.10 }
        if b.contains("7820HQ") { return 3.90 }
        if b.contains("7700HQ") { return 3.80 }
        if b.contains("6920HQ") { return 3.80 }
        if b.contains("6820HQ") { return 3.60 }
        if b.contains("6700HQ") { return 3.50 }
        if b.contains("4980HQ") { return 4.00 }
        if b.contains("4870HQ") { return 3.70 }

        // Generic fallback: Intel Turbo Boost is typically 1.6x - 1.8x base clock
        if base > 0 {
            return min(5.0, Double(round((base * 1.65) * 10) / 10))
        }
        return 4.50
    }

    func maxClockSummary(turboEnabled: Bool) -> String {
        if turboEnabled {
            if maxTurboFrequencyGHz > 0 {
                return String(format: "Max Clock: %.2f GHz (Turbo Active)", maxTurboFrequencyGHz)
            } else {
                return "Max Clock: Turbo Boost Active"
            }
        } else {
            if baseFrequencyGHz > 0 {
                return String(format: "Max Clock: %.2f GHz (Base Locked)", baseFrequencyGHz)
            } else {
                return "Max Clock: Base Clock Locked"
            }
        }
    }

    func start(interval: TimeInterval = 2.0) {
        guard !isRunning else { return }
        isRunning = true

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .milliseconds(250)
        )

        t.setEventHandler { [weak self] in
            self?.tick()
        }

        timer = t
        t.resume()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.cancel()
        timer = nil
        clearPrevCpuInfo()
    }

    func updateInterval(_ interval: TimeInterval) {
        stop()
        start(interval: interval)
    }

    private func clearPrevCpuInfo() {
        if let prev = prevCpuInfo {
            let size = vm_size_t(prevNumCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: prev)), size)
            prevCpuInfo = nil
            prevNumCpuInfo = 0
        }
    }

    private func tick() {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return }

        var totalUsage = 0.0

        if let prevCpuInfo = prevCpuInfo {
            var inUse: Int64 = 0
            var total: Int64 = 0

            for i in 0..<Int(numCPUsU) {
                let base = Int(CPU_STATE_MAX) * i

                let u = Int64(cpuInfo[base + Int(CPU_STATE_USER)] - prevCpuInfo[base + Int(CPU_STATE_USER)])
                let s = Int64(cpuInfo[base + Int(CPU_STATE_SYSTEM)] - prevCpuInfo[base + Int(CPU_STATE_SYSTEM)])
                let n = Int64(cpuInfo[base + Int(CPU_STATE_NICE)] - prevCpuInfo[base + Int(CPU_STATE_NICE)])
                let id = Int64(cpuInfo[base + Int(CPU_STATE_IDLE)] - prevCpuInfo[base + Int(CPU_STATE_IDLE)])

                let coreInUse = u + s + n
                let coreTotal = coreInUse + id

                inUse += coreInUse
                total += coreTotal
            }

            if total > 0 {
                totalUsage = (Double(inUse) / Double(total)) * 100.0
            }
        }

        clearPrevCpuInfo()
        prevCpuInfo = cpuInfo
        prevNumCpuInfo = numCpuInfo

        let stress = CPUStressLevel.from(usage: totalUsage)
        self.currentUsage = totalUsage
        self.currentLevel = stress

        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(totalUsage, stress)
        }
    }
}
