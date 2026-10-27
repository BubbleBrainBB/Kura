import AppKit
import Foundation

enum LibraryError: LocalizedError {
    case notALibrary(URL)
    case alreadyExists(URL)

    var errorDescription: String? {
        switch self {
        case .notALibrary(let url): return "“\(url.lastPathComponent)”不是 Kura 资源库。"
        case .alreadyExists(let url): return "“\(url.lastPathComponent)”已经存在。"
        }
    }
}

/// 一个打开的资源库：磁盘上的 .kura 文件夹。
/// 结构：library.sqlite（元数据）、items/<id>/<原文件>、thumbs/<id>.jpg|png
@MainActor
final class LibraryStore: ObservableObject {
    nonisolated static let fileExtension = "kura"
    nonisolated static let databaseName = "library.sqlite"
    static let folderColors = Palette.folderHexes

    let url: URL
    private let db: Database
    @Published private(set) var items: [Item] = []
    @Published private(set) var folders: [Folder] = []
    /// 标签的上级和图标。只有设过上级、图标，或者单独建的标签才在这里
    @Published private(set) var tagInfo: [String: TagInfo] = [:]
    @Published var importProgress: ImportProgress?
    @Published var lastError: String?
    var activeImports = 0
    private var indexByID: [String: Int] = [:]

    var name: String { url.deletingPathExtension().lastPathComponent }

    nonisolated static func isLibrary(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(databaseName).path)
    }

    static func create(at url: URL) throws -> LibraryStore {
        if FileManager.default.fileExists(atPath: url.path) {
            if isLibrary(url) { return try LibraryStore(url: url) }
            throw LibraryError.alreadyExists(url)
        }
        return try LibraryStore(url: url)
    }

    static func open(at url: URL) throws -> LibraryStore {
        guard isLibrary(url) else { throw LibraryError.notALibrary(url) }
        return try LibraryStore(url: url)
    }

    private init(url: URL) throws {
        self.url = url
        let fm = FileManager.default
        try fm.createDirectory(at: url.appendingPathComponent("items"), withIntermediateDirectories: true)
        try fm.createDirectory(at: url.appendingPathComponent("thumbs"), withIntermediateDirectories: true)
        db = try Database(path: url.appendingPathComponent(Self.databaseName).path)
        try Schema.migrate(db)
        try reload()
    }

    // MARK: - 查询

    func item(_ id: String) -> Item? {
        indexByID[id].map { items[$0] }
    }

    func fileURL(for item: Item) -> URL {
        url.appendingPathComponent(item.path)
    }

    func thumbURL(for item: Item) -> URL? {
        item.thumb.map { url.appendingPathComponent($0) }
    }

    /// 如果文件就在本资源库里（比如从网格拖到侧边栏），返回对应的素材
    func item(atFileURL fileURL: URL) -> Item? {
        let root = url.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(root) else { return nil }
        let relative = String(path.dropFirst(root.count))
        return items.first { $0.path == relative }
    }

    func contains(fileURL: URL) -> Bool {
        let root = url.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        return fileURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root)
    }

    var counts: LibraryCounts {
        var counts = LibraryCounts()
        let lineage = Dictionary(uniqueKeysWithValues: tagInfo.keys.map { ($0, ancestors(of: $0)) })
        for item in items {
            if item.deletedAt != nil {
                counts.trash += 1
                continue
            }
            counts.all += 1
            counts.bytes += item.size
            if item.folderIDs.isEmpty { counts.uncategorized += 1 }
            if item.tags.isEmpty { counts.untagged += 1 }
            if item.viewedAt != nil { counts.recent += 1 }
            for id in item.folderIDs { counts.folders[id, default: 0] += 1 }
            // 父标签也算上，同一个素材只算一次
            var tags = Set(item.tags)
            for tag in item.tags { tags.formUnion(lineage[tag] ?? []) }
            for tag in tags { counts.tags[tag, default: 0] += 1 }
        }
        return counts
    }

    /// 素材用到的标签，加上单独建的标签（比如还没有素材的父标签）
    var allTags: [String] {
        Set(items.filter { $0.deletedAt == nil }.flatMap(\.tags)).union(tagInfo.keys)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - 读取

    private static let itemColumns = "id, name, ext, kind, path, thumb, thumb_rev, size, width, height, duration, rating, note, url, colors, added_at, modified_at, viewed_at, deleted_at, cover_time"

    func reload() throws {
        var tags: [String: [String]] = [:]
        for row in try db.query("SELECT item_id, tag FROM item_tags ORDER BY rowid") {
            tags[row.string(0), default: []].append(row.string(1))
        }
        var links: [String: [String]] = [:]
        for row in try db.query("SELECT item_id, folder_id FROM item_folders ORDER BY rowid") {
            links[row.string(0), default: []].append(row.string(1))
        }
        items = try db.query("SELECT \(Self.itemColumns) FROM items ORDER BY added_at").map { r in
            let id = r.string(0)
            return Item(
                id: id, name: r.string(1), ext: r.string(2), kind: ItemKind(rawValue: r.string(3)) ?? .other,
                path: r.string(4), thumb: r.optionalString(5), thumbRev: r.int(6), size: Int64(r.int(7)),
                width: r.int(8), height: r.int(9), duration: r.optionalDouble(10), rating: r.int(11),
                note: r.string(12), url: r.string(13),
                colors: r.string(14).split(separator: ",").map(String.init),
                tags: tags[id] ?? [], folderIDs: links[id] ?? [],
                addedAt: r.date(15), modifiedAt: r.date(16), viewedAt: r.optionalDate(17), deletedAt: r.optionalDate(18),
                coverTime: r.optionalDouble(19)
            )
        }
        folders = try db.query("SELECT id, name, parent_id, color, sort FROM folders ORDER BY sort, created_at").map { r in
            Folder(id: r.string(0), name: r.string(1), parentID: r.optionalString(2), color: r.string(3), sort: r.int(4))
        }
        tagInfo = try loadTagInfo()
        rebuildIndex()
    }

    private func loadTagInfo() throws -> [String: TagInfo] {
        Dictionary(uniqueKeysWithValues: try db.query("SELECT name, parent, icon FROM tags").map {
            ($0.string(0), TagInfo(parent: $0.optionalString(1), icon: $0.optionalString(2)))
        })
    }

    private func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
    }

    // MARK: - 修改素材

    func insert(_ newItems: [Item]) {
        guard !newItems.isEmpty else { return }
        persist(newItems)
        items.append(contentsOf: newItems)
        rebuildIndex()
    }

    func update(_ ids: [String], touch: Bool = true, _ change: (inout Item) -> Void) {
        var copy = items
        var changed: [Item] = []
        for id in ids {
            guard let index = indexByID[id] else { continue }
            var item = copy[index]
            change(&item)
            guard item != copy[index] else { continue }
            if touch { item.modifiedAt = Date() }
            copy[index] = item
            changed.append(item)
        }
        guard !changed.isEmpty else { return }
        items = copy
        persist(changed)
    }

    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update([id]) { $0.name = trimmed }
    }

    func setRating(_ ids: [String], _ rating: Int) {
        update(ids) { $0.rating = max(0, min(5, rating)) }
    }

    func setNote(_ id: String, _ note: String) {
        update([id]) { $0.note = note }
    }

    func setSourceURL(_ id: String, _ url: String) {
        update([id]) { $0.url = url.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func addTag(_ ids: [String], _ tag: String) {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        update(ids) { if !$0.tags.contains(tag) { $0.tags.append(tag) } }
    }

    func removeTag(_ ids: [String], _ tag: String) {
        update(ids) { $0.tags.removeAll { $0 == tag } }
    }

    /// 「Moonshot/Kimi K4」：沿路径建好上下级，再把最后一级打到素材上
    func addTagPath(_ ids: [String], _ path: String) {
        let parts = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let leaf = parts.last else { return }
        for (parent, child) in zip(parts, parts.dropFirst()) { setParent(child, parent) }
        addTag(ids, leaf)
    }

    func renameTag(_ old: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !new.isEmpty, new != old else { return }
        let ids = items.filter { $0.tags.contains(old) }.map(\.id)
        update(ids) { item in
            item.tags = item.tags.map { $0 == old ? new : $0 }
            var seen = Set<String>()
            item.tags = item.tags.filter { seen.insert($0).inserted }
        }
        let source = tagInfo[old], target = tagInfo[new]
        editTags {
            for (name, var child) in tagInfo where child.parent == old {
                child.parent = new
                try saveTag(name, child)
            }
            guard source != nil || target != nil else { return }
            // 改成一个已有的标签名就是合并：保留那个标签自己的上级和图标
            var merged = target ?? TagInfo(parent: source?.parent)
            if merged.icon == nil { merged.icon = source?.icon }
            if let parent = merged.parent, parent == old || withDescendants(new).contains(parent) { merged.parent = nil }
            try saveTag(new, merged)
            try saveTag(old, nil)
        }
        if let icon = source?.icon, target?.icon != nil {
            try? FileManager.default.removeItem(at: url.appendingPathComponent(icon))
        }
    }

    /// 子标签不跟着删，移到上一级
    func deleteTag(_ tag: String) {
        removeTag(items.filter { $0.tags.contains(tag) }.map(\.id), tag)
        let info = tagInfo[tag]
        editTags {
            for (name, var child) in tagInfo where child.parent == tag {
                child.parent = info?.parent
                try saveTag(name, child)
            }
            if info != nil { try saveTag(tag, nil) }
        }
        if let icon = info?.icon { try? FileManager.default.removeItem(at: url.appendingPathComponent(icon)) }
    }

    // MARK: - 标签层级

    /// 单独建一个标签，可以还没有素材
    func createTag(_ name: String, parent: String?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if tagInfo[name] == nil { editTags { try saveTag(name, TagInfo()) } }
        if let parent { setParent(name, parent) }
    }

    /// 不能放进自己或自己的下级里
    func canMove(_ tag: String, under parent: String?) -> Bool {
        guard let parent else { return true }
        return !withDescendants(tag).contains(parent)
    }

    func setParent(_ tag: String, _ parent: String?) {
        guard canMove(tag, under: parent), tagInfo[tag] == nil || tagInfo[tag]?.parent != parent else { return }
        editTags {
            // 父标签也登记下来，这样它没有素材时也还在
            if let parent, tagInfo[parent] == nil { try saveTag(parent, TagInfo()) }
            var info = tagInfo[tag] ?? TagInfo()
            info.parent = parent
            try saveTag(tag, info)
        }
    }

    func parent(of tag: String) -> String? {
        tagInfo[tag]?.parent
    }

    /// 从顶层到直接上级
    func ancestors(of tag: String) -> [String] {
        var chain: [String] = []
        var seen: Set<String> = [tag]
        var current = tagInfo[tag]?.parent
        while let parent = current, seen.insert(parent).inserted {
            chain.insert(parent, at: 0)
            current = tagInfo[parent]?.parent
        }
        return chain
    }

    /// 自己加上所有下级
    func withDescendants(_ tag: String) -> Set<String> {
        var result: Set<String> = [tag]
        var grew = true
        while grew {
            grew = false
            for (name, info) in tagInfo where !result.contains(name) {
                if let parent = info.parent, result.contains(parent) {
                    result.insert(name)
                    grew = true
                }
            }
        }
        return result
    }

    /// 上级 → 下级标签（按名字排序），顶层的键是 nil
    var tagChildren: [String?: [String]] {
        var result: [String?: [String]] = [:]
        for tag in allTags {
            // 数据里万一绕成了圈，就当顶层显示，不至于整串消失
            let chain = ancestors(of: tag)
            let rooted = chain.first.map { tagInfo[$0]?.parent == nil } ?? true
            result[rooted ? tagInfo[tag]?.parent : nil, default: []].append(tag)
        }
        return result
    }

    /// 「Moonshot › Kimi K3.1 Pro」
    func tagPath(_ tag: String) -> String {
        (ancestors(of: tag) + [tag]).joined(separator: " › ")
    }

    /// 没有图标的标签用圆点，颜色跟顶层标签一致
    func tagColorKey(_ tag: String) -> String {
        ancestors(of: tag).first ?? tag
    }

    private func saveTag(_ name: String, _ info: TagInfo?) throws {
        if let info {
            try db.run(
                "INSERT INTO tags (name, parent, icon) VALUES (?, ?, ?) ON CONFLICT(name) DO UPDATE SET parent = excluded.parent, icon = excluded.icon",
                [name, info.parent, info.icon]
            )
        } else {
            try db.run("DELETE FROM tags WHERE name = ?", [name])
        }
        tagInfo[name] = info
    }

    /// 几步标签修改放在一个事务里；失败时回滚，内存里的也重新读一遍
    private func editTags(_ body: () throws -> Void) {
        do {
            try db.transaction(body)
        } catch {
            if let saved = try? loadTagInfo() { tagInfo = saved }
            report(error)
        }
    }

    // MARK: - 标签图标

    static let tagIconExtensions: Set<String> = ["svg", "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "pdf"]

    /// 图标来自哪个标签：自己，或者最近的有图标的上级
    func tagIconSource(_ tag: String) -> String? {
        ([tag] + ancestors(of: tag).reversed()).first { tagInfo[$0]?.icon != nil }
    }

    func tagIconURL(_ tag: String) -> URL? {
        tagIconSource(tag).flatMap { tagInfo[$0]?.icon }.map { url.appendingPathComponent($0) }
    }

    /// 把图片复制进资源库的 tag-icons/ 作为标签图标。SVG 的 em 之类尺寸换成像素，系统才能按正常大小显示。
    func setTagIcon(_ tag: String, from source: URL) {
        let ext = source.pathExtension.lowercased()
        guard Self.tagIconExtensions.contains(ext) else {
            lastError = "“\(source.lastPathComponent)”不是图片，不能用作标签图标。"
            return
        }
        let relative = "tag-icons/\(UUID().uuidString).\(ext)"
        let destination = url.appendingPathComponent(relative)
        let fm = FileManager.default
        let old = tagInfo[tag]?.icon
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if ext == "svg", let text = try? String(contentsOf: source, encoding: .utf8) {
                try SVGIcon.normalized(text).write(to: destination, atomically: true, encoding: .utf8)
            } else {
                try fm.copyItem(at: source, to: destination)
            }
            var info = tagInfo[tag] ?? TagInfo()
            info.icon = relative
            try saveTag(tag, info)
            if let old { try? fm.removeItem(at: url.appendingPathComponent(old)) }
        } catch {
            try? fm.removeItem(at: destination)
            report(error)
        }
    }

    /// 只去掉标签自己的图标；有上级图标的话会改用上级的
    func removeTagIcon(_ tag: String) {
        guard var info = tagInfo[tag], let old = info.icon else { return }
        info.icon = nil
        editTags { try saveTag(tag, info) }
        try? FileManager.default.removeItem(at: url.appendingPathComponent(old))
    }

    func addToFolder(_ ids: [String], _ folderID: String) {
        update(ids) { if !$0.folderIDs.contains(folderID) { $0.folderIDs.append(folderID) } }
    }

    func removeFromFolder(_ ids: [String], _ folderID: String) {
        update(ids) { $0.folderIDs.removeAll { $0 == folderID } }
    }

    func moveToTrash(_ ids: [String]) {
        let now = Date()
        update(ids, touch: false) { $0.deletedAt = now }
    }

    func restore(_ ids: [String]) {
        update(ids, touch: false) { $0.deletedAt = nil }
    }

    func markViewed(_ id: String) {
        update([id], touch: false) { $0.viewedAt = Date() }
    }

    /// 永久删除：素材文件移到系统废纸篓，数据库记录删除
    func deletePermanently(_ ids: [String]) {
        let fm = FileManager.default
        let doomed = Set(ids)
        for item in items where doomed.contains(item.id) {
            let directory = fileURL(for: item).deletingLastPathComponent()
            try? fm.trashItem(at: directory, resultingItemURL: nil)
            if let thumb = thumbURL(for: item) { try? fm.removeItem(at: thumb) }
        }
        do {
            try db.transaction {
                for id in doomed { try db.run("DELETE FROM items WHERE id = ?", [id]) }
            }
        } catch {
            report(error)
        }
        items.removeAll { doomed.contains($0.id) }
        rebuildIndex()
    }

    func emptyTrash() {
        deletePermanently(items.filter { $0.deletedAt != nil }.map(\.id))
    }

    /// 把视频某一帧设为封面，重新生成缩略图和颜色
    func setCover(_ id: String, seconds: Double) async {
        guard let item = item(id) else { return }
        let fileURL = fileURL(for: item)
        let libraryURL = url
        let result = await Task.detached { () -> (String, [String])? in
            guard let image = try? await MediaProbe.videoFrame(fileURL, at: seconds),
                  let thumb = Thumbnailer.save(image, libraryURL: libraryURL, id: id) else { return nil }
            return (thumb, ColorExtractor.palette(of: image))
        }.value
        guard let result else {
            lastError = "无法截取这一帧。"
            return
        }
        update([id]) {
            $0.thumb = result.0
            $0.thumbRev += 1
            $0.colors = result.1
            $0.coverTime = seconds
        }
    }

    // MARK: - 文件夹

    func folder(_ id: String) -> Folder? {
        folders.first { $0.id == id }
    }

    func childFolders(of parentID: String?) -> [Folder] {
        folders.filter { $0.parentID == parentID }
    }

    func hasChildren(_ id: String) -> Bool {
        folders.contains { $0.parentID == id }
    }

    /// 按树形顺序展开的文件夹列表，用于菜单
    func folderOutline() -> [(folder: Folder, depth: Int)] {
        var result: [(Folder, Int)] = []
        func walk(_ parent: String?, _ depth: Int) {
            for folder in childFolders(of: parent) {
                result.append((folder, depth))
                walk(folder.id, depth + 1)
            }
        }
        walk(nil, 0)
        return result
    }

    @discardableResult
    func createFolder(named name: String, parentID: String? = nil) -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = Folder(
            id: UUID().uuidString,
            name: trimmed.isEmpty ? "未命名文件夹" : trimmed,
            parentID: parentID,
            color: Self.folderColors[folders.count % Self.folderColors.count],
            sort: folders.count
        )
        do {
            try db.run(
                "INSERT INTO folders (id, name, parent_id, color, sort, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                [folder.id, folder.name, folder.parentID, folder.color, folder.sort, Date()]
            )
            folders.append(folder)
        } catch {
            report(error)
        }
        return folder
    }

    func renameFolder(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        do {
            try db.run("UPDATE folders SET name = ? WHERE id = ?", [trimmed, id])
            folders[index].name = trimmed
        } catch {
            report(error)
        }
    }

    /// 删除文件夹及子文件夹，素材本身保留
    func deleteFolder(_ id: String) {
        do {
            try db.run("DELETE FROM folders WHERE id = ?", [id])
            try reload()
        } catch {
            report(error)
        }
    }

    // MARK: - 写入

    private static let upsertSQL = """
    INSERT INTO items (\(itemColumns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        name = excluded.name, ext = excluded.ext, kind = excluded.kind, path = excluded.path,
        thumb = excluded.thumb, thumb_rev = excluded.thumb_rev, size = excluded.size,
        width = excluded.width, height = excluded.height, duration = excluded.duration,
        rating = excluded.rating, note = excluded.note, url = excluded.url, colors = excluded.colors,
        added_at = excluded.added_at, modified_at = excluded.modified_at,
        viewed_at = excluded.viewed_at, deleted_at = excluded.deleted_at, cover_time = excluded.cover_time
    """

    private func persist(_ changed: [Item]) {
        do {
            try db.transaction {
                for item in changed {
                    try db.run(Self.upsertSQL, [
                        item.id, item.name, item.ext, item.kind.rawValue, item.path, item.thumb, item.thumbRev,
                        item.size, item.width, item.height, item.duration, item.rating, item.note, item.url,
                        item.colors.joined(separator: ","), item.addedAt, item.modifiedAt, item.viewedAt, item.deletedAt,
                        item.coverTime,
                    ])
                    try db.run("DELETE FROM item_tags WHERE item_id = ?", [item.id])
                    for tag in item.tags {
                        try db.run("INSERT OR IGNORE INTO item_tags (item_id, tag) VALUES (?, ?)", [item.id, tag])
                    }
                    try db.run("DELETE FROM item_folders WHERE item_id = ?", [item.id])
                    for folderID in item.folderIDs {
                        try db.run("INSERT OR IGNORE INTO item_folders (item_id, folder_id) VALUES (?, ?)", [item.id, folderID])
                    }
                }
            }
        } catch {
            report(error)
        }
    }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }
}
