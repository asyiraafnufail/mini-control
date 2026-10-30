import AppKit
import ServiceManagement

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let cpuMonitor: CPUMonitor
    private let powerMonitor: PowerMonitor
    private let turboController = TurboBoostController.shared

    // Menu items
    private let cpuMenuItem = NSMenuItem(title: "CPU Load: Calculating...", action: nil, keyEquivalent: "")
    private let clockMenuItem = NSMenuItem(title: "Max Clock: Calculating...", action: nil, keyEquivalent: "")
    private let powerMenuItem = NSMenuItem(title: "Power: Reading...", action: nil, keyEquivalent: "")
    private let turboMenuItem = NSMenuItem(title: "Turbo Boost", action: #selector(toggleTurboBoost), keyEquivalent: "t")
    private let showWattMenuItem = NSMenuItem(title: "Show Watt in Menu Bar", action: #selector(toggleShowWatt), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var lastACConnected: Bool?

    // User preferences
    private var showWattInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: "showWattInMenuBar") }
        set { UserDefaults.standard.set(newValue, forKey: "showWattInMenuBar") }
    }

    private var currentInterval: TimeInterval {
        get {
            let val = UserDefaults.standard.double(forKey: "refreshInterval")
            return val > 0 ? val : 2.0
        }
        set { UserDefaults.standard.set(newValue, forKey: "refreshInterval") }
    }

    init(cpuMonitor: CPUMonitor, powerMonitor: PowerMonitor) {
        self.cpuMonitor = cpuMonitor
        self.powerMonitor = powerMonitor
        super.init()

        setupMenu()
        setupBindings()
        updateStatusItemAppearance()
        updateClockMenuItem()
    }

    private func setupMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        // 1. CPU Load Item
        cpuMenuItem.isEnabled = false
        menu.addItem(cpuMenuItem)

        // 1b. Real Max Clock Speed Item
        clockMenuItem.isEnabled = false
        updateClockMenuItem()
        menu.addItem(clockMenuItem)

        // 2. Power Item
        powerMenuItem.isEnabled = false
        menu.addItem(powerMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Turbo Boost Toggle
        turboMenuItem.target = self
        updateTurboMenuItem()
        menu.addItem(turboMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Preferences Submenu
        let prefsMenu = NSMenu(title: "Preferences")

        showWattMenuItem.target = self
        showWattMenuItem.state = showWattInMenuBar ? .on : .off
        prefsMenu.addItem(showWattMenuItem)

        launchAtLoginMenuItem.target = self
        launchAtLoginMenuItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        prefsMenu.addItem(launchAtLoginMenuItem)

        prefsMenu.addItem(NSMenuItem.separator())

        // Polling rate submenu
        let intervalMenu = NSMenu(title: "Polling Rate")
        for sec in [1.0, 2.0, 5.0] {
            let item = NSMenuItem(
                title: "\(Int(sec))s",
                action: #selector(selectInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = sec
            item.state = (sec == currentInterval) ? .on : .off
            intervalMenu.addItem(item)
        }

        let intervalMenuItem = NSMenuItem(title: "Polling Rate", action: nil, keyEquivalent: "")
        intervalMenuItem.submenu = intervalMenu
        prefsMenu.addItem(intervalMenuItem)

        prefsMenu.addItem(NSMenuItem.separator())

        // Install Helper tool option
        let helperItem = NSMenuItem(
            title: "Helper Tool Setup...",
            action: #selector(showHelperInstallAlert),
            keyEquivalent: ""
        )
        helperItem.target = self
        prefsMenu.addItem(helperItem)

        let prefsMenuItem = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefsMenuItem.submenu = prefsMenu
        menu.addItem(prefsMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quit
        let quitItem = NSMenuItem(
            title: "Quit MiniControl",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupBindings() {
        cpuMonitor.onUpdate = { [weak self] usage, level in
            self?.handleCPUUpdate(usage: usage, level: level)
        }

        powerMonitor.onUpdate = { [weak self] status in
            self?.handlePowerUpdate(status: status)
        }

        turboController.onStateChange = { [weak self] _ in
            self?.updateTurboMenuItem()
            self?.updateClockMenuItem()
            self?.updateStatusItemAppearance()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        turboController.refreshRealStatus()
        powerMonitor.refresh()
        updateClockMenuItem()
        launchAtLoginMenuItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func handleCPUUpdate(usage: Double, level: CPUStressLevel) {
        cpuMenuItem.title = String(format: "CPU Load: %.1f%%", usage)
        updateStatusItemAppearance()
    }

    private func handlePowerUpdate(status: PowerStatus) {
        powerMenuItem.title = status.menuSummary
        updateStatusItemAppearance()

        if let prevAC = lastACConnected, prevAC != status.isACConnected {
            // Power source transitioned (AC plugged/unplugged) -> ensure Turbo Boost state remains enforced
            turboController.reapplyStateOnWake()
        }
        lastACConnected = status.isACConnected
    }

    private func updateClockMenuItem() {
        let isEnabled = (turboController.currentState == .enabled)
        clockMenuItem.title = cpuMonitor.maxClockSummary(turboEnabled: isEnabled)
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        let isTBEnabled = (turboController.currentState == .enabled)

        // Single combined icon: Heartbeat waveform + real-time Turbo Boost dot
        button.image = HeartbeatIcon.icon(
            for: cpuMonitor.currentLevel,
            turboBoostEnabled: isTBEnabled
        )
        button.imagePosition = .imageLeading

        if showWattInMenuBar, let power = powerMonitor.currentStatus {
            let wattText = power.isCharging ? String(format: "+%.0fW", power.instantaneousWatts) :
                           power.isACConnected ? "AC" :
                           String(format: "%.0fW", abs(power.instantaneousWatts))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            button.attributedTitle = NSAttributedString(string: wattText, attributes: attributes)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
        }
    }

    private func updateTurboMenuItem() {
        switch turboController.currentState {
        case .unsupported:
            turboMenuItem.title = "Turbo Boost: Not Supported"
            turboMenuItem.state = .off
            turboMenuItem.isEnabled = false
        case .enabled:
            turboMenuItem.title = "Turbo Boost: Enabled"
            turboMenuItem.state = .on
            turboMenuItem.isEnabled = true
        case .disabled:
            turboMenuItem.title = "Turbo Boost: Disabled"
            turboMenuItem.state = .off
            turboMenuItem.isEnabled = true
        }
    }

    @objc private func toggleTurboBoost() {
        let willEnable = (turboController.currentState != .enabled)
        turboMenuItem.isEnabled = false
        turboController.toggle(enabled: willEnable) { [weak self] result in
            DispatchQueue.main.async {
                self?.turboMenuItem.isEnabled = true
                switch result {
                case .success:
                    self?.updateTurboMenuItem()
                    self?.updateClockMenuItem()
                    self?.updateStatusItemAppearance()
                case .failure(let error):
                    let alert = NSAlert()
                    alert.messageText = "Turbo Boost Error"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    @objc private func toggleShowWatt() {
        showWattInMenuBar.toggle()
        showWattMenuItem.state = showWattInMenuBar ? .on : .off
        updateStatusItemAppearance()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let sec = sender.representedObject as? TimeInterval else { return }
        currentInterval = sec
        cpuMonitor.updateInterval(sec)

        if let parent = sender.parent {
            for item in parent.submenu?.items ?? [] {
                item.state = (item == sender) ? .on : .off
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginMenuItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginMenuItem.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login"
            alert.informativeText = "Untuk mengaktifkan Launch at Login, pastikan MiniControl.app berada di dalam folder /Applications."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func showHelperInstallAlert() {
        let alert = NSAlert()
        alert.messageText = "Turbo Boost Helper Setup"
        if turboController.isHelperInstalled {
            alert.informativeText = "Helper tool is installed at /usr/local/bin/minicontrol-tb.\nHardware MSR toggling is fully enabled."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } else {
            let cmd = "sudo \"/Applications/MiniControl.app/Contents/Resources/install_helper.sh\""
            alert.informativeText = "To allow hardware MSR clock control without password prompts, run this command in Terminal:\n\n\(cmd)"
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Cancel")
            let resp = alert.runModal()
            if resp == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd, forType: .string)
            }
        }
    }
}
