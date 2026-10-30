import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private let cpuMonitor: CPUMonitor
    private let powerMonitor: PowerMonitor
    private let turboController = TurboBoostController.shared

    // Menu items
    private let cpuMenuItem = NSMenuItem(title: "CPU: Calculating...", action: nil, keyEquivalent: "")
    private let powerMenuItem = NSMenuItem(title: "Power: Reading...", action: nil, keyEquivalent: "")
    private let turboMenuItem = NSMenuItem(title: "Turbo Boost", action: #selector(toggleTurboBoost), keyEquivalent: "t")
    private let showWattMenuItem = NSMenuItem(title: "Show Watt in Menu Bar", action: #selector(toggleShowWatt), keyEquivalent: "")

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
    }

    private func setupMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        // 1. CPU Item
        cpuMenuItem.isEnabled = false
        menu.addItem(cpuMenuItem)

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
    }

    private func handleCPUUpdate(usage: Double, level: CPUStressLevel) {
        cpuMenuItem.title = String(format: "CPU Load: %.1f%%", usage)
        updateStatusItemAppearance()
    }

    private func handlePowerUpdate(status: PowerStatus) {
        powerMenuItem.title = status.menuSummary
        updateStatusItemAppearance()
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }

        button.image = HeartbeatIcon.icon(for: cpuMonitor.currentLevel)
        button.imagePosition = .imageLeading

        if showWattInMenuBar, let power = powerMonitor.currentStatus {
            let wattText = power.isCharging ? String(format: " +%.0fW", power.instantaneousWatts) :
                           power.isACConnected ? " AC" :
                           String(format: " %.0fW", abs(power.instantaneousWatts))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
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
        case .helperRequired:
            turboMenuItem.title = "Turbo Boost: Install Helper..."
            turboMenuItem.state = .off
            turboMenuItem.isEnabled = true
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
        if turboController.currentState == .helperRequired {
            showHelperInstallAlert()
            return
        }

        let willEnable = (turboController.currentState != .enabled)
        turboController.toggle(enabled: willEnable) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.updateTurboMenuItem()
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

        // Update submenu checkmarks
        if let parent = sender.parent {
            for item in parent.submenu?.items ?? [] {
                item.state = (item == sender) ? .on : .off
            }
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func showHelperInstallAlert() {
        let alert = NSAlert()
        alert.messageText = "Privileged Helper Required"
        alert.informativeText = "Writing to Intel MSR registers to toggle Turbo Boost requires a root helper daemon.\n\nRun MiniControl setup script with administrator rights to configure."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
