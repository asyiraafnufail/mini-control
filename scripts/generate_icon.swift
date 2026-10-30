import AppKit

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let scale = size / 1024.0

    // Apple squircle rect (824x824 centered in 1024x1024)
    let margin = 100.0 * scale
    let rectSize = 824.0 * scale
    let iconRect = CGRect(x: margin, y: margin, width: rectSize, height: rectSize)
    let cornerRadius = 185.0 * scale
    let squirclePath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Shadow behind squircle
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -18 * scale),
        blur: 32 * scale,
        color: NSColor.black.withAlphaComponent(0.45).cgColor
    )
    ctx.addPath(squirclePath)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for inner drawing
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    // Base background gradient (Deep Space Slate / Graphite)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            end: CGPoint(x: iconRect.midX, y: iconRect.minY),
            options: []
        )
    }

    // Subtle radial highlight at top
    let radialColors = [
        NSColor.white.withAlphaComponent(0.12).cgColor,
        NSColor.clear.cgColor
    ] as CFArray
    if let radialGradient = CGGradient(colorsSpace: colorSpace, colors: radialColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            radialGradient,
            startCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.95),
            startRadius: 0,
            endCenter: CGPoint(x: iconRect.midX, y: iconRect.maxY * 0.95),
            endRadius: rectSize * 0.6,
            options: []
        )
    }

    // Subtle grid pattern (ECG monitor texture)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.04).cgColor)
    ctx.setLineWidth(1.0 * scale)
    let gridSpacing = 48.0 * scale
    var gx = iconRect.minX
    while gx <= iconRect.maxX {
        ctx.move(to: CGPoint(x: gx, y: iconRect.minY))
        ctx.addLine(to: CGPoint(x: gx, y: iconRect.maxY))
        gx += gridSpacing
    }
    var gy = iconRect.minY
    while gy <= iconRect.maxY {
        ctx.move(to: CGPoint(x: iconRect.minX, y: gy))
        ctx.addLine(to: CGPoint(x: iconRect.maxX, y: gy))
        gy += gridSpacing
    }
    ctx.strokePath()

    // 1. Draw glowing ECG waveform
    let centerY = iconRect.midY
    let ecgPath = CGMutablePath()

    let pts: [(CGFloat, CGFloat)] = [
        (180, 512),
        (300, 512),
        (350, 560), // P wave
        (400, 512),
        (440, 360), // Q wave
        (512, 730), // R wave tall peak
        (580, 390), // S wave deep dip
        (620, 512),
        (670, 540), // T wave
        (720, 512),
        (840, 512)
    ]

    let mapPt = { (pt: (CGFloat, CGFloat)) -> CGPoint in
        CGPoint(
            x: iconRect.minX + (pt.0 / 1024.0) * rectSize,
            y: iconRect.minY + (pt.1 / 1024.0) * rectSize
        )
    }

    ecgPath.move(to: mapPt(pts[0]))
    for i in 1..<pts.count {
        ecgPath.addLine(to: mapPt(pts[i]))
    }

    // Glow under waveform
    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 24.0 * scale,
        color: NSColor(calibratedRed: 0.0, green: 0.95, blue: 0.75, alpha: 0.7).cgColor
    )
    ctx.addPath(ecgPath)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.1, green: 0.95, blue: 0.70, alpha: 0.9).cgColor)
    ctx.setLineWidth(16.0 * scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Sharp foreground waveform stroke
    ctx.addPath(ecgPath)
    ctx.setStrokeColor(NSColor(calibratedRed: 0.85, green: 1.0, blue: 0.95, alpha: 1.0).cgColor)
    ctx.setLineWidth(10.0 * scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // 2. Turbo Boost Electric Spark / Dot at upper right
    let sparkCenter = CGPoint(
        x: iconRect.minX + rectSize * 0.78,
        y: iconRect.minY + rectSize * 0.78
    )
    let sparkRadius = 32.0 * scale

    ctx.saveGState()
    ctx.setShadow(
        offset: .zero,
        blur: 28.0 * scale,
        color: NSColor(calibratedRed: 0.1, green: 0.8, blue: 1.0, alpha: 0.85).cgColor
    )
    ctx.setFillColor(NSColor(calibratedRed: 0.2, green: 0.85, blue: 1.0, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: CGRect(
        x: sparkCenter.x - sparkRadius,
        y: sparkCenter.y - sparkRadius,
        width: sparkRadius * 2,
        height: sparkRadius * 2
    ))
    ctx.restoreGState()

    // Inner bright core of spark
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(
        x: sparkCenter.x - sparkRadius * 0.5,
        y: sparkCenter.y - sparkRadius * 0.5,
        width: sparkRadius,
        height: sparkRadius
    ))

    ctx.restoreGState() // unclip

    // Squircle subtle inner border (Apple glass edge effect)
    ctx.addPath(squirclePath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    ctx.setLineWidth(2.5 * scale)
    ctx.strokePath()

    image.unlockFocus()
    return image
}

// Generate iconset
let fm = FileManager.default
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let projectDir = URL(fileURLWithPath: scriptDir).deletingLastPathComponent().path
let iconsetDir = "\(projectDir)/AppIcon.iconset"
let resourcesDir = "\(projectDir)/Resources"

try? fm.removeItem(atPath: iconsetDir)
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

print("Rendering high-resolution macOS icons...")
for (base, scale, filename) in sizes {
    let px = CGFloat(base * scale)
    let img = renderIcon(size: px)
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let path = "\(iconsetDir)/\(filename)"
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

// Compile with Apple's iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", "\(resourcesDir)/AppIcon.icns"]
try? process.run()
process.waitUntilExit()

try? fm.removeItem(atPath: iconsetDir)
print("==> AppIcon.icns generated successfully in Resources/AppIcon.icns")
