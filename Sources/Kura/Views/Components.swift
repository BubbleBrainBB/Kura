import AppKit
import ImageIO
import SwiftUI

// MARK: - 缩略图

enum ImageLoader {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 1500
        return cache
    }()

    static func cached(_ key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    static func load(_ url: URL, key: String) async -> NSImage? {
        if let hit = cached(key) { return hit }
        let cgImage = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key as NSString)
        return image
    }
}

struct ThumbnailView: View {
    let url: URL?
    let rev: Int
    let kind: ItemKind
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    init(url: URL?, rev: Int, kind: ItemKind, contentMode: ContentMode = .fill) {
        self.url = url
        self.rev = rev
        self.kind = kind
        self.contentMode = contentMode
        _image = State(initialValue: ImageLoader.cached(Self.key(url, rev)))
    }

    private static func key(_ url: URL?, _ rev: Int) -> String {
        "\(url?.path ?? "")#\(rev)"
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color.primary.opacity(0.06))
                GlyphIcon(placeholderGlyph, size: 24, lineWidth: 1.25)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: Self.key(url, rev)) {
            guard let url else {
                image = nil
                return
            }
            image = await ImageLoader.load(url, key: Self.key(url, rev))
        }
    }

    private var placeholderGlyph: Glyph {
        switch kind {
        case .image: .image
        case .video: .video
        case .other: .document
        }
    }
}

struct VideoBadge: View {
    let duration: Double

    var body: some View {
        HStack(spacing: 3) {
            GlyphIcon(.play, size: 9, lineWidth: 1, filled: true)
            Text(Format.duration(duration)).font(.system(size: 10, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: Capsule())
    }
}

// MARK: - 应用图标

/// 应用图标“海鼠壁”：墨色底上的白色斜格纹，一格朱红。和 scripts/make-icon.swift 画的是同一个图形。
struct AppIconView: View {
    var size: CGFloat = 84

    /// 格纹参数，坐标沿用设计稿的 100×100 viewBox。小尺寸下格子更疏、线更粗
    private var lattice: (spacing: CGFloat, lineWidth: CGFloat, c: CGFloat, k: CGFloat) {
        switch size {
        case ...20: (28, 7, 0, 100)
        case ...40: (20, 5.5, 0, 100)
        case ...70: (14, 4, 0, 114)
        default: (14, 3.2, 0, 114)
        }
    }

    var body: some View {
        let lattice = lattice
        Canvas { context, canvasSize in
            // 主体对应 viewBox 里的 10…90
            let unit = canvasSize.width / 80
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 10) * unit, y: (y - 10) * unit) }
            let body = Path(roundedRect: CGRect(origin: .zero, size: canvasSize), cornerRadius: 18 * unit, style: .continuous)
            context.clip(to: body)
            context.fill(body, with: .linearGradient(
                Gradient(colors: [Color(hex: "#2E313A"), Color(hex: "#15161A")]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: canvasSize.height)
            ))

            let s = lattice.spacing
            let top = CGPoint(x: (lattice.k - lattice.c) / 2, y: (lattice.k + lattice.c) / 2)
            var accent = Path()
            accent.move(to: point(top.x, top.y))
            accent.addLine(to: point(top.x + s / 2, top.y + s / 2))
            accent.addLine(to: point(top.x, top.y + s))
            accent.addLine(to: point(top.x - s / 2, top.y + s / 2))
            accent.closeSubpath()
            context.fill(accent, with: .color(Color(hex: "#D9573B")))

            var lines = Path()
            var offset = lattice.c.truncatingRemainder(dividingBy: s) - 5 * s
            while offset <= 100 {
                lines.move(to: point(0, offset))
                lines.addLine(to: point(100, 100 + offset))
                offset += s
            }
            offset = lattice.k.truncatingRemainder(dividingBy: s)
            while offset <= 200 {
                lines.move(to: point(0, offset))
                lines.addLine(to: point(100, offset - 100))
                offset += s
            }
            context.stroke(lines, with: .color(Color(hex: "#E9E6DF")), style: StrokeStyle(lineWidth: lattice.lineWidth * unit, lineCap: .round))
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: 18 * size / 80, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.2), radius: size / 14, y: size / 28)
    }
}

// MARK: - 标签

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 标签图标

@MainActor
enum TagIconCache {
    private static var images: [String: NSImage] = [:]

    /// SVG 当作单色图标（跟随文字颜色），位图保持原色
    static func image(at url: URL) -> NSImage? {
        if let cached = images[url.path] { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = url.pathExtension.lowercased() == "svg"
        images[url.path] = image
        return image
    }
}

struct TagIconImage: View {
    let url: URL
    var size: CGFloat = 16

    var body: some View {
        if let image = TagIconCache.image(at: url) {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            GlyphIcon(.tag, size: size)
        }
    }
}

/// 标签的标记：设了图标就显示图标，否则是按名字分配颜色的小圆点
struct TagMark: View {
    let iconURL: URL?
    let tag: String
    var size: CGFloat = 16

    var body: some View {
        if let iconURL {
            TagIconImage(url: iconURL, size: size)
        } else {
            Circle()
                .fill(Palette.tag(tag))
                .frame(width: size * 0.45, height: size * 0.45)
                .frame(width: size, height: size)
        }
    }
}

extension TagMark {
    /// 子标签没设图标就用上级的；圆点颜色跟顶层标签一致
    @MainActor init(store: LibraryStore, tag: String, size: CGFloat = 16) {
        self.init(iconURL: store.tagIconURL(tag), tag: store.tagColorKey(tag), size: size)
    }
}

struct TagChip: View {
    let title: String
    var glyph: Glyph?
    var iconURL: URL?
    /// 没有图标时，用这个标签名的颜色画小圆点
    var dotTag: String?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            if let glyph {
                GlyphIcon(glyph, size: 12)
            }
            if let iconURL {
                TagIconImage(url: iconURL, size: 12)
                    .foregroundStyle(.secondary)
            } else if let dotTag {
                Circle().fill(Palette.tag(dotTag)).frame(width: 6, height: 6)
            }
            Text(title).font(.system(size: 12))
            if let onRemove {
                Button(action: onRemove) {
                    GlyphIcon(.close, size: 10, lineWidth: 1.75)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("移除")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

struct TagEditor: View {
    let store: LibraryStore
    let tags: [String]
    /// 收到的可能是「上级/名称」这样的路径，交给 store.addTagPath 处理
    var onAdd: (String) -> Void
    var onRemove: (String) -> Void
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tags.isEmpty {
                FlowLayout {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(title: tag, iconURL: store.tagIconURL(tag), dotTag: store.tagColorKey(tag)) { onRemove(tag) }
                            .help(store.tagPath(tag))
                    }
                }
            }
            TextField("添加标签，回车确认", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            let query = draft.trimmingCharacters(in: .whitespaces)
            if !query.isEmpty {
                suggestions(for: query)
            }
        }
    }

    /// 按名字匹配，上级用灰色写在前面
    @ViewBuilder
    private func suggestions(for query: String) -> some View {
        let all = store.allTags
        let matches = all.filter { !tags.contains($0) && $0.localizedCaseInsensitiveContains(query) }.prefix(8)
        let exists = all.contains { $0.caseInsensitiveCompare(query) == .orderedSame }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(matches), id: \.self) { tag in
                SuggestionRow(action: { add(tag) }) {
                    TagMark(store: store, tag: tag, size: 13)
                        .foregroundStyle(.secondary)
                    let parents = store.ancestors(of: tag)
                    (parents.isEmpty ? Text("") : Text(parents.joined(separator: " › ") + " › ").foregroundStyle(.secondary))
                        + Text(tag)
                }
            }
            if !exists {
                if !matches.isEmpty { Divider().padding(.vertical, 3) }
                SuggestionRow(action: commit) {
                    GlyphIcon(.plus, size: 13).foregroundStyle(.secondary)
                    Text("新建标签「\(query.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " › "))」")
                }
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))
        if !query.contains("/") {
            Text("输入「上级/名称」可以直接建成子标签")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func add(_ tag: String) {
        onAdd(tag)
        draft = ""
    }

    /// 支持用逗号一次输入多个标签；和已有标签只差大小写时用已有的写法
    private func commit() {
        let all = store.allTags
        let parts = draft.split(whereSeparator: { $0 == "," || $0 == "，" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for part in parts {
            onAdd(all.first { $0.caseInsensitiveCompare(part) == .orderedSame } ?? part)
        }
        draft = ""
    }
}

private struct SuggestionRow<Label: View>: View {
    var action: () -> Void
    @ViewBuilder var label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) { label }
                .font(.system(size: 12))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background(hovered ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct RatingControl: View {
    let rating: Int
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    onChange(value == rating ? 0 : value)
                } label: {
                    GlyphIcon(.star, size: 19, lineWidth: 1.25, filled: value <= rating)
                        .foregroundStyle(value <= rating ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) 星")
            }
        }
        .font(.system(size: 15))
    }
}

// MARK: - 工具

enum Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

extension Color {
    init(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespaces)
        if string.hasPrefix("#") { string.removeFirst() }
        let value = UInt64(string, radix: 16) ?? 0x888888
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Color {
    /// 浅色、深色模式各用一个颜色，随系统外观自动切换
    init(light: String, dark: String) {
        let lightColor = NSColor(Color(hex: light))
        let darkColor = NSColor(Color(hex: dark))
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }
}

extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}

@MainActor
enum ItemActions {
    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func copyFiles(_ urls: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

enum KeyboardFocus {
    /// 正在文本框里输入时，网格和预览的快捷键要让路
    @MainActor
    static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }
}

enum DropHelper {
    /// 从拖放内容里取出文件 URL，回到主线程后回调
    static func fileURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) -> Bool {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                if !urls.isEmpty { completion(urls) }
            }
        }
        return true
    }
}
