import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("MacPulse.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon context creation failed") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let p = CGFloat(pixels)
        let rect = NSRect(x: p * 0.07, y: p * 0.07, width: p * 0.86, height: p * 0.86)
        let shape = NSBezierPath(roundedRect: rect, xRadius: p * 0.2, yRadius: p * 0.2)
        NSColor(calibratedRed: 0.065, green: 0.075, blue: 0.12, alpha: 1).setFill(); shape.fill()
        NSColor(calibratedRed: 0.32, green: 0.65, blue: 1, alpha: 1).setStroke()
        let pulse = NSBezierPath(); pulse.lineWidth = p * 0.055; pulse.lineCapStyle = .round; pulse.lineJoinStyle = .round
        pulse.move(to: NSPoint(x: p * 0.22, y: p * 0.49))
        for (x, y) in [(0.34, 0.49), (0.41, 0.65), (0.50, 0.30), (0.59, 0.74), (0.66, 0.49), (0.78, 0.49)] { pulse.line(to: NSPoint(x: p * x, y: p * y)) }
        pulse.stroke(); NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon generation failed") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
