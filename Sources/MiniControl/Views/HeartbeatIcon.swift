import AppKit

final class HeartbeatIcon {
    private static let size = NSSize(width: 22, height: 18)
    private static var cachedIcons: [CPUStressLevel: NSImage] = [:]

    static func icon(for level: CPUStressLevel) -> NSImage {
        if let cached = cachedIcons[level] {
            return cached
        }

        let image = renderIcon(level: level)
        cachedIcons[level] = image
        return image
    }

    private static func renderIcon(level: CPUStressLevel) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let color: NSColor
        switch level {
        case .normal:
            color = NSColor.systemGreen
        case .medium:
            color = NSColor.systemYellow
        case .high:
            color = NSColor.systemRed
        }

        // Draw ECG / Heartbeat waveform
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // Geometry points across width (0 .. 22)
        // Baseline around y = 9
        path.move(to: NSPoint(x: 1.5, y: 9.0))
        path.line(to: NSPoint(x: 5.5, y: 9.0))
        path.line(to: NSPoint(x: 7.5, y: 11.5))   // small P wave
        path.line(to: NSPoint(x: 9.5, y: 9.0))
        path.line(to: NSPoint(x: 11.0, y: 3.0))   // Q wave dip
        path.line(to: NSPoint(x: 13.5, y: 16.0))  // R wave tall peak
        path.line(to: NSPoint(x: 16.0, y: 4.5))   // S wave dip
        path.line(to: NSPoint(x: 17.5, y: 9.0))
        path.line(to: NSPoint(x: 20.5, y: 9.0))

        color.setStroke()
        path.stroke()

        image.unlockFocus()
        image.isTemplate = false // Preserve system colors in menu bar
        return image
    }
}
