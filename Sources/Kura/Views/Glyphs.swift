import AppKit
import SwiftUI

/// 全应用统一的线条图标。路径和设计稿“侧栏图标 · 线条风”一致，画在 16pt 网格上。
enum Glyph: CaseIterable {
    case all, uncategorized, untagged, recent, trash, folder, smartFolder, tag, library
    case sidebar, inspector, importFile, search, plus, chevronDown, upDown
    case chevronLeft, chevronRight, close, sort, external, image, video, document
    case star, play, warning, checkCircle, emptySelection, panels
    case pause, stepBack, stepForward, loop, volume, volumeMuted, fullscreen
    case viewOptions, thumbSmall, thumbLarge

    /// “还没有”的状态用虚线表示：未分类、未加标签、未选择
    var dashed: Bool { self == .uncategorized || self == .untagged || self == .emptySelection }

    var pathData: String {
        switch self {
        case .all: Self.rr(2.5, 2.5, 4.5, 4.5, 1.25) + Self.rr(9, 2.5, 4.5, 4.5, 1.25) + Self.rr(2.5, 9, 4.5, 4.5, 1.25) + Self.rr(9, 9, 4.5, 4.5, 1.25)
        case .folder, .uncategorized: Self.folderPath
        case .tag, .untagged: "M2.5 3.75A1.25 1.25 0 0 1 3.75 2.5H7.4c.4 0 .78.16 1.06.44l4.6 4.6a1.5 1.5 0 0 1 0 2.12l-3.4 3.4a1.5 1.5 0 0 1-2.12 0l-4.6-4.6A1.5 1.5 0 0 1 2.5 7.4zM5.5 5.5h.01"
        case .recent: Self.circle(8, 8, 5.5) + "M8 5.25V8l1.75 1.25"
        case .trash: "M3 4.5h10M6.25 4.5V3.25c0-.41.34-.75.75-.75h2c.41 0 .75.34.75.75V4.5M4.25 4.5l.55 7.7a1.5 1.5 0 0 0 1.5 1.3h3.4a1.5 1.5 0 0 0 1.5-1.3l.55-7.7"
        case .smartFolder: Self.folderPath + "M5.75 8.5h4.5M6.75 10.5h2.5"
        case .library: Self.rr(2.5, 2.75, 11, 3, 1) + "M3.5 5.75v5.5a1.75 1.75 0 0 0 1.75 1.75h5.5a1.75 1.75 0 0 0 1.75-1.75v-5.5M6.5 8.5h3"
        case .sidebar: Self.rr(2, 3, 12, 10, 2) + "M6.25 3v10"
        case .inspector: Self.rr(2, 3, 12, 10, 2) + "M9.75 3v10"
        case .importFile: "M8 2.5v7M5.25 6.75 8 9.5l2.75-2.75M2.75 10v1.25a1.75 1.75 0 0 0 1.75 1.75h7a1.75 1.75 0 0 0 1.75-1.75V10"
        case .search: Self.circle(7.25, 7.25, 4.25) + "M10.5 10.5l3 3"
        case .plus: "M8 3.5v9M3.5 8h9"
        case .chevronDown: "M5.5 6.75 8 9.25l2.5-2.5"
        case .upDown: "M5.5 6.25 8 3.75l2.5 2.5M5.5 9.75 8 12.25l2.5-2.5"
        case .chevronLeft: "M9.5 4 5.5 8l4 4"
        case .chevronRight: "M6.5 4l4 4-4 4"
        case .close: "M4.5 4.5l7 7M11.5 4.5l-7 7"
        case .sort: "M5 3v10M2.75 10.75 5 13l2.25-2.25M11 13V3M8.75 5.25 11 3l2.25 2.25"
        case .external: "M9 3h4v4M13 3 7.5 8.5M11.25 9.5v2.75a1.25 1.25 0 0 1-1.25 1.25H4.25A1.25 1.25 0 0 1 3 12.25V6.5a1.25 1.25 0 0 1 1.25-1.25H7"
        case .image: Self.rr(2.5, 3, 11, 10, 1.75) + "M5.75 6.25h.01M2.75 11l3-3 2.75 2.75 1.5-1.5 2.75 2.75"
        case .video: Self.rr(2, 4, 8.5, 8, 1.75) + "M10.5 7.25l3.5-2v5.5l-3.5-2"
        case .document: "M4.25 2.5h4.5l3 3v7.75a.75.75 0 0 1-.75.75h-6.75a.75.75 0 0 1-.75-.75v-10a.75.75 0 0 1 .75-.75zM8.75 2.5v3h3"
        case .star: "M8 2.8L9.53 6.3 13.33 6.67 10.47 9.2 11.29 12.93 8 11 4.71 12.93 5.53 9.2 2.67 6.67 6.47 6.3z"
        case .play: "M5.5 3.75v8.5L12.5 8z"
        case .warning: "M8 2.75 14 13.25H2zM8 6.75v3M8 11.5h.01"
        case .checkCircle: Self.circle(8, 8, 5.75) + "M5.5 8.25l1.75 1.75 3.25-3.5"
        case .emptySelection: Self.rr(2.5, 2.5, 11, 11, 2.5)
        case .panels: Self.rr(2, 3, 12, 10, 2) + "M5.75 3v10M10.25 3v10"
        case .pause: Self.rr(4, 3.5, 2.75, 9, 1) + Self.rr(9.25, 3.5, 2.75, 9, 1)
        case .stepBack: "M4 4v8M12 4v8L6.5 8z"
        case .stepForward: "M12 4v8M4 4v8l5.5-4z"
        case .loop: "M3 7.5v-.75A2.75 2.75 0 0 1 5.75 4H13M11 2l2 2-2 2M13 8.5v.75A2.75 2.75 0 0 1 10.25 12H3M5 14l-2-2 2-2"
        case .volume: Self.speaker + "M10.75 5.75a3 3 0 0 1 0 4.5M12.5 4a5.5 5.5 0 0 1 0 8"
        case .volumeMuted: Self.speaker + "M11 6.25l3 3.5M14 6.25l-3 3.5"
        case .viewOptions: "M2.75 4.5h6.5M12.25 4.5h1M2.75 11.5h1M6.75 11.5h6.5" + Self.circle(10.75, 4.5, 1.5) + Self.circle(5.25, 11.5, 1.5)
        case .thumbSmall: Self.rr(4.5, 4.5, 7, 7, 1.5)
        case .thumbLarge: Self.rr(2, 2, 12, 12, 2.5)
        case .fullscreen: "M2.75 6V3.75a1 1 0 0 1 1-1H6M10 2.75h2.25a1 1 0 0 1 1 1V6M13.25 10v2.25a1 1 0 0 1-1 1H10M6 13.25H3.75a1 1 0 0 1-1-1V10"
        }
    }

    private static let speaker = "M2.75 6.25h2.5L8.5 3.5v9L5.25 9.75h-2.5z"

    private static let folderPath = "M2.5 4.75A1.75 1.75 0 0 1 4.25 3H6.3c.46 0 .9.18 1.23.51l.71.71c.33.33.77.51 1.23.51h2.28a1.75 1.75 0 0 1 1.75 1.75v4.77A1.75 1.75 0 0 1 11.75 13h-7.5A1.75 1.75 0 0 1 2.5 11.25z"

    private static func rr(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
        "M\(x + r) \(y)h\(w - 2 * r)a\(r) \(r) 0 0 1 \(r) \(r)v\(h - 2 * r)a\(r) \(r) 0 0 1 \(-r) \(r)"
            + "h\(-(w - 2 * r))a\(r) \(r) 0 0 1 \(-r) \(-r)v\(-(h - 2 * r))a\(r) \(r) 0 0 1 \(r) \(-r)z"
    }

    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        "M\(cx - r) \(cy)a\(r) \(r) 0 1 0 \(2 * r) 0a\(r) \(r) 0 1 0 \(-2 * r) 0z"
    }
}

struct GlyphIcon: View {
    let glyph: Glyph
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.5
    /// 实心版本（选中的星、播放角标），描边同色，保持圆角
    var filled = false

    init(_ glyph: Glyph, size: CGFloat = 16, lineWidth: CGFloat = 1.5, filled: Bool = false) {
        self.glyph = glyph
        self.size = size
        self.lineWidth = lineWidth
        self.filled = filled
    }

    var body: some View {
        let scale = size / 16
        let stroke = StrokeStyle(
            lineWidth: lineWidth * scale,
            lineCap: .round,
            lineJoin: .round,
            dash: glyph.dashed ? [1.8 * scale, 1.7 * scale] : []
        )
        ZStack {
            if filled {
                GlyphShape(glyph: glyph).fill()
            }
            GlyphShape(glyph: glyph).stroke(style: stroke)
        }
        .frame(width: size, height: size)
    }
}

extension Glyph {
    /// 菜单按钮（Menu）的标签只显示 Image，所以把线条图标渲染成模板图片，颜色仍跟随系统
    @MainActor
    func image(size: CGFloat = 16, lineWidth: CGFloat = 1.5) -> Image {
        let key = "\(self)-\(size)-\(lineWidth)"
        if let cached = GlyphImageCache.images[key] { return Image(nsImage: cached) }
        let renderer = ImageRenderer(content: GlyphIcon(self, size: size, lineWidth: lineWidth).foregroundStyle(Color.black))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = true
        GlyphImageCache.images[key] = image
        return Image(nsImage: image)
    }
}

@MainActor
private enum GlyphImageCache {
    static var images: [String: NSImage] = [:]
}

struct GlyphShape: Shape {
    let glyph: Glyph

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        return SVGPath.path(for: glyph)
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

/// 只支持图标用到的 SVG 路径命令：M L H V C A Z（大小写都支持）
enum SVGPath {
    static func path(for glyph: Glyph) -> Path {
        parse(glyph.pathData)
    }

    static func parse(_ data: String) -> Path {
        var reader = Reader(Array(data.unicodeScalars))
        var path = Path()
        var command: Character = "M"
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        while !reader.atEnd {
            if let letter = reader.readCommand() {
                command = letter
                if command == "Z" || command == "z" {
                    path.closeSubpath()
                    current = subpathStart
                    continue
                }
            }
            let relative = command.isLowercase
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command {
            case "M", "m":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = point(x, y)
                subpathStart = current
                path.move(to: current)
                // 紧跟在 M 后面的坐标按 L 处理
                command = relative ? "l" : "L"
            case "L", "l":
                guard let x = reader.number(), let y = reader.number() else { return path }
                current = point(x, y)
                path.addLine(to: current)
            case "H", "h":
                guard let x = reader.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
            case "V", "v":
                guard let y = reader.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
            case "C", "c":
                guard let x1 = reader.number(), let y1 = reader.number(),
                      let x2 = reader.number(), let y2 = reader.number(),
                      let x = reader.number(), let y = reader.number() else { return path }
                let control1 = point(x1, y1), control2 = point(x2, y2), end = point(x, y)
                path.addCurve(to: end, control1: control1, control2: control2)
                current = end
            case "A", "a":
                guard let rx = reader.number(), let _ = reader.number(), let _ = reader.number(),
                      let large = reader.number(), let sweep = reader.number(),
                      let x = reader.number(), let y = reader.number() else { return path }
                let end = point(x, y)
                addArc(to: &path, from: current, to: end, radius: rx, largeArc: large != 0, sweep: sweep != 0)
                current = end
            default:
                return path
            }
        }
        return path
    }

    /// 图标里的弧都是正圆、不旋转，按 SVG 规范把端点形式换算成圆心形式
    private static func addArc(to path: inout Path, from start: CGPoint, to end: CGPoint, radius: CGFloat, largeArc: Bool, sweep: Bool) {
        guard radius > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        var r = radius
        let lambda = (dx * dx + dy * dy) / (r * r)
        if lambda > 1 { r *= lambda.squareRoot() }
        let numerator = max(0, r * r - dx * dx - dy * dy)
        let denominator = dx * dx + dy * dy
        let coefficient = (largeArc != sweep ? 1 : -1) * (numerator / denominator).squareRoot()
        let cxPrime = coefficient * dy
        let cyPrime = -coefficient * dx
        let center = CGPoint(x: cxPrime + (start.x + end.x) / 2, y: cyPrime + (start.y + end.y) / 2)
        let startAngle = atan2(dy - cyPrime, dx - cxPrime)
        let endAngle = atan2(-dy - cyPrime, -dx - cxPrime)
        // SVG 的 sweep=1 是角度递增方向；SwiftUI 的 clockwise 参数含义正好相反
        path.addArc(center: center, radius: r, startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: !sweep)
    }

    private struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

        var atEnd: Bool {
            mutating get {
                skipSeparators()
                return index >= scalars.count
            }
        }

        mutating func skipSeparators() {
            while index < scalars.count, scalars[index] == " " || scalars[index] == "," || scalars[index] == "\n" {
                index += 1
            }
        }

        mutating func readCommand() -> Character? {
            skipSeparators()
            guard index < scalars.count, CharacterSet.letters.contains(scalars[index]) else { return nil }
            defer { index += 1 }
            return Character(scalars[index])
        }

        /// 支持紧凑写法：".71.71"、"1.5-2"
        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = index
            if index < scalars.count, scalars[index] == "-" || scalars[index] == "+" { index += 1 }
            var sawDot = false
            var sawDigit = false
            while index < scalars.count {
                let c = scalars[index]
                if c == "." {
                    if sawDot { break }
                    sawDot = true
                } else if ("0"..."9").contains(c) {
                    sawDigit = true
                } else {
                    break
                }
                index += 1
            }
            guard sawDigit else {
                index = begin
                return nil
            }
            return Double(String(String.UnicodeScalarView(scalars[begin..<index]))).map { CGFloat($0) }
        }
    }
}

/// 文件夹和标签的颜色：低饱和，深色模式下自动提亮
enum Palette {
    static let folderHexes = ["#C8604B", "#3E8A6B", "#7A6CC4", "#A9802A", "#4F78B8"]

    private static let darkVariants: [String: String] = [
        "#C8604B": "#E8876F", "#3E8A6B": "#5DB58F", "#7A6CC4": "#A296E3",
        "#A9802A": "#DDB04E", "#4F78B8": "#7FA3DE",
    ]

    /// 第一版资源库里存的是旧的高饱和颜色，显示时换成新色板里对应的颜色
    private static let legacy: [String: String] = [
        "#FF6B57": "#C8604B", "#3CC29A": "#3E8A6B", "#9D87FF": "#7A6CC4",
        "#FF8A5C": "#A9802A", "#3B9BFF": "#4F78B8", "#F4C430": "#A9802A",
    ]

    static func folder(_ hex: String) -> Color {
        let light = legacy[hex.uppercased()] ?? hex
        return dynamic(light: light, dark: darkVariants[light.uppercased()] ?? light)
    }

    /// 标签没有存颜色，按名字稳定地分配一个
    static func tag(_ name: String) -> Color {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return folder(folderHexes[sum % folderHexes.count])
    }

    private static func dynamic(light: String, dark: String) -> Color {
        let lightColor = NSColor(Color(hex: light))
        let darkColor = NSColor(Color(hex: dark))
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}
