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

    init() {
        var mib = [CTL_HW, HW_NCPU]
        var size = MemoryLayout<natural_t>.size
        sysctl(&mib, 2, &numCPUs, &size, nil, 0)
    }

    deinit {
        stop()
        clearPrevCpuInfo()
    }

    func start(interval: TimeInterval = 2.0) {
        guard !isRunning else { return }
        isRunning = true

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .milliseconds(250) // Leeway allows CPU idle consolidation
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

        // Deallocate old buffer and keep current as previous
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
