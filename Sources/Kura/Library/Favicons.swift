import AppKit

/// 来源链接前面的网站图标。某个网站第一次显示时，去这个网站自己那里取一次 favicon，存进缓存目录，
/// 以后都从缓存读；取不到也记一笔，七天内不再去试
@MainActor
enum Favicons {
    private static var images: [String: NSImage] = [:]
    private static var missing: Set<String> = []
    private static var loading: [String: Task<Data?, Never>] = [:]

    static func cached(_ host: String) -> NSImage? {
        images[host]
    }

    static func image(for host: String) async -> NSImage? {
        if let hit = images[host] { return hit }
        if missing.contains(host) { return nil }
        let task = loading[host] ?? Task.detached(priority: .utility) { await FaviconLoader.data(for: host) }
        loading[host] = task
        let data = await task.value
        loading[host] = nil
        guard let data, let image = NSImage(data: data), image.size.width > 0 else {
            missing.insert(host)
            return nil
        }
        images[host] = image
        return image
    }
}

private enum FaviconLoader {
    private static let retryAfter: TimeInterval = 7 * 24 * 3600
    private static let maxBytes = 1_000_000

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        ]
        return URLSession(configuration: config)
    }()

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "Kura", directoryHint: .isDirectory)
            .appending(path: "favicons", directoryHint: .isDirectory)
    }

    static func data(for host: String) async -> Data? {
        let file = directory.appending(path: host)
        let marker = directory.appending(path: host + ".missing")
        if let data = try? Data(contentsOf: file) { return data }
        if let date = (try? marker.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) < retryAfter {
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = await fetch(host) {
            try? data.write(to: file)
            try? FileManager.default.removeItem(at: marker)
            return data
        }
        try? Data().write(to: marker)
        return nil
    }

    /// 先试 /favicon.ico；不行再看首页里 <link rel="icon"> 写的地址；最后试 apple-touch-icon
    private static func fetch(_ host: String) async -> Data? {
        guard let root = URL(string: "https://\(host)/") else { return nil }
        if let data = await image(at: root.appending(path: "favicon.ico")) { return data }
        for url in await declaredIcons(on: root) {
            if let data = await image(at: url) { return data }
        }
        return await image(at: root.appending(path: "apple-touch-icon.png"))
    }

    private static func image(at url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty, data.count <= maxBytes,
              let image = NSImage(data: data), image.size.width > 0 else { return nil }
        return data
    }

    /// 首页里声明的图标，尺寸大的排前面（16pt 显示，大图缩小更清楚）
    private static func declaredIcons(on root: URL) async -> [URL] {
        guard let (data, response) = try? await session.data(from: root),
              let html = String(data: data.prefix(300_000), encoding: .utf8) ?? String(data: data.prefix(300_000), encoding: .isoLatin1) else { return [] }
        let base = response.url ?? root
        var found: [(url: URL, size: Int)] = []
        for tag in html.matches(of: #/<link\b[^>]*>/#.ignoresCase()) {
            let text = String(tag.output)
            guard let rel = attribute("rel", in: text)?.lowercased(), rel.contains("icon"), !rel.contains("mask"),
                  let href = attribute("href", in: text),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL else { continue }
            let size = attribute("sizes", in: text)
                .flatMap { $0.split(separator: "x").first }
                .flatMap { Int($0) } ?? (rel.contains("apple") ? 180 : 32)
            found.append((url, size))
        }
        return found.sorted { $0.size > $1.size }.map(\.url)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try? Regex<(Substring, Substring)>("\(name)\\s*=\\s*[\"']([^\"']*)[\"']").ignoresCase()
        guard let pattern, let match = tag.firstMatch(of: pattern) else { return nil }
        return String(match.output.1)
    }
}
