// 生成 Resources/AppIcon.icns：Kura 的“海鼠壁”图标。
// 墨色底上是仓房外墙的白色斜格纹，其中一格是朱红色的“宝贝”，与设计稿“Kura 图标 · 六个抽象方向”的 A 一致。
// 用法：swift scripts/make-icon.swift [输出路径]
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// 格纹参数：小尺寸下格子更疏、线更粗，否则会糊成一片
struct Lattice {
    var spacing: CGFloat
    var lineWidth: CGFloat
    /// 朱红格子所在的两条斜线（y = x + c 与 y = -x + k）
    var c: CGFloat
    var k: CGFloat

    static func forPixels(_ pixels: Int) -> Lattice {
        switch pixels {
        case ...16: Lattice(spacing: 28, lineWidth: 7, c: 0, k: 100)
        case ...32: Lattice(spacing: 20, lineWidth: 5.5, c: 0, k: 100)
        case ...64: Lattice(spacing: 14, lineWidth: 4, c: 0, k: 114)
        default: Lattice(spacing: 14, lineWidth: 3.2, c: 0, k: 114)
        }
    }
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // 设计稿用 100×100 的 viewBox，主体在 10…90，对应 macOS 图标网格（1024 画布里 824 的主体）
    let unit = CGFloat(pixels) / 100
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * unit, y: (100 - y) * unit) }
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * unit, y: (100 - y - h) * unit, width: w * unit, height: h * unit)
    }
    let lattice = Lattice.forPixels(pixels)

    let body = NSBezierPath(roundedRect: rect(10, 10, 80, 80), xRadius: 18 * unit, yRadius: 18 * unit)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 2 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -0.8 * unit)
    shadow.set()
    color(0x202228).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(starting: color(0x2E313A), ending: color(0x15161A))?.draw(in: body, angle: -90)

    // 朱红格子：四个顶点是两组斜线的交点
    let s = lattice.spacing
    let top = (x: (lattice.k - lattice.c) / 2, y: (lattice.k + lattice.c) / 2)
    let accent = NSBezierPath()
    accent.move(to: point(top.x, top.y))
    accent.line(to: point(top.x + s / 2, top.y + s / 2))
    accent.line(to: point(top.x, top.y + s))
    accent.line(to: point(top.x - s / 2, top.y + s / 2))
    accent.close()
    color(0xD9573B).setFill()
    accent.fill()

    let lines = NSBezierPath()
    var offset = lattice.c.truncatingRemainder(dividingBy: s) - 5 * s
    while offset <= 100 {
        lines.move(to: point(0, offset))
        lines.line(to: point(100, 100 + offset))
        offset += s
    }
    offset = lattice.k.truncatingRemainder(dividingBy: s)
    while offset <= 200 {
        lines.move(to: point(0, offset))
        lines.line(to: point(100, offset - 100))
        offset += s
    }
    lines.lineWidth = lattice.lineWidth * unit
    lines.lineCapStyle = .round
    color(0xE9E6DF).setStroke()
    lines.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let rim = NSBezierPath(roundedRect: rect(10.5, 10.5, 79, 79), xRadius: 17.5 * unit, yRadius: 17.5 * unit)
    rim.lineWidth = max(1, 0.5 * unit)
    NSColor.white.withAlphaComponent(0.1).setStroke()
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
    (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x"),
]
for (pixels, name) in sizes {
    try render(pixels).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "已生成 \(output)" : "iconutil 失败")
