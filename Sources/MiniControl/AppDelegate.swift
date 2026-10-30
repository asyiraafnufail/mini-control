import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cpuMonitor: CPUMonitor!
    private var powerMonitor: PowerMonitor!
    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon explicitly for menu-bar-only app
        NSApp.setActivationPolicy(.accessory)

        // Initialize monitors
        cpuMonitor = CPUMonitor()
        powerMonitor = PowerMonitor()

        // Initialize status bar UI
        statusBarController = StatusBarController(
            cpuMonitor: cpuMonitor,
            powerMonitor: powerMonitor
        )

        // Setup power/sleep awareness to pause timers when Mac sleeps
        setupSleepObservers()

        // Start CPU sampling
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        cpuMonitor.start(interval: interval > 0 ? interval : 2.0)
    }

    private func setupSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter

        // Stop polling completely when screen or system sleeps
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cpuMonitor.stop()
        }

        center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cpuMonitor.stop()
        }

        // Resume when screen or system wakes
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeMonitors()
        }

        center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeMonitors()
        }
    }

    private func resumeMonitors() {
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        cpuMonitor.start(interval: interval > 0 ? interval : 2.0)
        powerMonitor.refresh()
    }
}
