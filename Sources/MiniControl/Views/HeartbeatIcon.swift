import AppKit

final class HeartbeatIcon {
    // Total size with harmonic 5pt rhythmic spacing:
    // [1.5 .. 18.0 (Waveform)] -- 4.5pt gap -- [24.5 (Dot r=2.2)] -- 5.3pt margin
    private static let size = NSSize(width: 32, height: 18)
    private static var cache: [String: NSImage] = [:]

    static func icon(for level: CPUStressLevel, turboBoostEnabled: Bool) -> NSImage {
        let key = "\(level)-\(turboBoostEnabled)"
        if let cached = cache[key] {
            return cached
        }

        let image = renderIcon(level: level, turboBoostEnabled: turboBoostEnabled)
        cache[key] = image
        return image
    }

    private static func renderIcon(level: CPUStressLevel, turboBoostEnabled: Bool) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        // 1. Color for heartbeat
        let strokeColor: NSColor
        switch level {
        case .normal:
            strokeColor = NSColor.systemGreen
        case .medium:
            strokeColor = NSColor.systemYellow
        case .high:
            strokeColor = NSColor.systemRed
        }

        // 2. Draw Heartbeat ECG waveform (x: 1.5 to 18.0, centered at y = 9.0)
        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: NSPoint(x: 1.5, y: 9.0))
        path.line(to: NSPoint(x: 4.5, y: 9.0))
        path.line(to: NSPoint(x: 6.5, y: 11.2))   // P wave
        path.line(to: NSPoint(x: 8.5, y: 9.0))
        path.line(to: NSPoint(x: 10.0, y: 4.0))   // Q wave dip
        path.line(to: NSPoint(x: 12.2, y: 15.5))  // R wave peak
        path.line(to: NSPoint(x: 14.5, y: 4.5))   // S wave dip
        path.line(to: NSPoint(x: 16.0, y: 9.0))
        path.line(to: NSPoint(x: 18.0, y: 9.0))

        strokeColor.setStroke()
        path.stroke()

        // 3. Draw Turbo Boost indicator dot
        // Dot center at x: 24.5 (creates exact 4.3pt gap from ECG end at 18.0)
        let dotCenter = NSPoint(x: 24.5, y: 9.0)
        let dotRadius: CGFloat = 2.2
        let dotRect = NSRect(
            x: dotCenter.x - dotRadius,
            y: dotCenter.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)

        if turboBoostEnabled {
            // Turbo Boost ON: Solid electric cyan dot
            NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.95, alpha: 1.0).setFill()
            dotPath.fill()
        } else {
            // Turbo Boost OFF: Crisp outline ring
            NSColor.secondaryLabelColor.withAlphaComponent(0.45).setStroke()
            dotPath.lineWidth = 1.1
            dotPath.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
