import AppKit
import UniformTypeIdentifiers

/// ⌘V 粘贴进资源库：Finder 里拷贝的文件、截图和网页里拷贝的图片、复制来的 SVG 代码。
/// 只在用户按下粘贴时读剪贴板，不在后台监听
@MainActor
enum PasteboardImport {
    enum Content {
        case files([URL])
        /// 剪贴板里只有数据没有文件：先写成临时文件再导入
        case file(URL, name: String, source: String)
    }

    /// 能直接存下来的图片格式，按优先顺序；TIFF 放最后，转成 PNG 再存
    private static let imageTypes: [(type: NSPasteboard.PasteboardType, ext: String)] = [
        (.png, "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (NSPasteboard.PasteboardType(UTType.webP.identifier), "webp"),
    ]
    private static let svgType = NSPasteboard.PasteboardType(UTType.svg.identifier)

    /// 给「编辑 › 粘贴」判断能不能点，只看类型，不读内容
    static func hasContent(_ pasteboard: NSPasteboard = .general) -> Bool {
        let types = Set(pasteboard.types ?? [])
        if types.contains(.fileURL) || types.contains(.tiff) || types.contains(svgType) { return true }
        if imageTypes.contains(where: { types.contains($0.type) }) { return true }
        return pasteboard.string(forType: .string).map(isSVG) ?? false
    }

    static func content(_ pasteboard: NSPasteboard = .general) -> Content? {
        // Finder 里拷贝文件时剪贴板也带着文件图标的图片，所以先看文件
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        let source = sourceURL(pasteboard)
        let name = suggestedName(from: source)
        for (type, ext) in imageTypes {
            if let data = pasteboard.data(forType: type), let file = write(data, name: name, ext: ext) {
                return .file(file, name: name, source: source ?? "")
            }
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
           let file = write(png, name: name, ext: "png") {
            return .file(file, name: name, source: source ?? "")
        }
        let svg = pasteboard.data(forType: svgType) ?? pasteboard.string(forType: .string).flatMap { isSVG($0) ? Data($0.utf8) : nil }
        if let svg, let file = write(svg, name: "粘贴的 SVG " + timestamp(), ext: "svg") {
            return .file(file, name: "粘贴的 SVG " + timestamp(), source: "")
        }
        return nil
    }

    private static func isSVG(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("<svg") || trimmed.hasPrefix("<?xml")) && trimmed.contains("</svg>")
    }

    /// 从网页拷贝图片时，剪贴板里常带着图片地址（Safari 放在 URL 里，Chrome 放在 HTML 的 <img src> 里）
    private static func sourceURL(_ pasteboard: NSPasteboard) -> String? {
        var candidates: [String] = []
        if let url = pasteboard.string(forType: .URL) { candidates.append(url) }
        if let html = pasteboard.string(forType: .html),
           let match = html.firstMatch(of: #/<img[^>]+src\s*=\s*["']([^"']+)["']/#.ignoresCase()) {
            candidates.append(String(match.output.1).replacingOccurrences(of: "&amp;", with: "&"))
        }
        return candidates.first { URL(string: $0)?.scheme?.hasPrefix("http") == true }
    }

    /// 地址最后一段像个文件名就用它，否则用「粘贴的图片 时间」
    private static func suggestedName(from source: String?) -> String {
        if let source, let url = URL(string: source) {
            let stem = url.deletingPathExtension().lastPathComponent.removingPercentEncoding ?? ""
            if !stem.isEmpty, stem.count <= 60, stem != "/", stem.contains(where: \.isLetter) {
                return stem
            }
        }
        return "粘贴的图片 " + timestamp()
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func write(_ data: Data, name: String, ext: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Kura-paste/\(UUID().uuidString)", directoryHint: .isDirectory)
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let file = directory.appending(path: "\(safeName).\(ext)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }
}

extension LibraryStore {
    /// 把剪贴板里的东西导入资源库，放进当前文件夹、打上当前标签。返回新素材的 id；剪贴板里没有能用的内容时返回 nil
    @discardableResult
    func pasteFromClipboard(into folderID: String?, tag: String?) -> [String]? {
        guard let content = PasteboardImport.content() else { return nil }
        let tags = tag.map { [$0] } ?? []
        switch content {
        case .files(let urls):
            return importFiles(urls, into: folderID, tags: tags)
        case .file(let file, let name, let source):
            let job = ImportJob(
                source: file,
                folderIDs: folderID.map { [$0] } ?? [],
                preset: ImportPreset(name: name, tags: tags, url: source)
            )
            enqueue([job])
            return [job.itemID]
        }
    }
}

extension Notification.Name {
    /// 「编辑 › 粘贴」在没有输入框接收时，交给主界面导入剪贴板
    static let kuraPaste = Notification.Name("KuraPaste")
}
