import AppKit
import SwiftUI

struct RecentLibrary: Codable, Identifiable, Hashable {
    var path: String
    var itemCount: Int
    var byteSize: Int64
    var lastOpened: Date

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var isAvailable: Bool { FileManager.default.fileExists(atPath: path) }
    var isInICloud: Bool { path.contains("/Library/Mobile Documents/") }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

@MainActor
final class AppModel: ObservableObject {
    /// 供 AppDelegate 处理 Dock 拖放时使用
    static weak var shared: AppModel?

    @Published private(set) var library: LibraryStore?
    @Published private(set) var recents: [RecentLibrary] = []
    @Published var errorMessage: String?
    /// 启动时正在恢复上次的资源库
    @Published private(set) var isRestoring = false

    private let recentsKey = "recentLibraries"
    private let lastLibraryKey = "lastLibraryPath"

    init() {
        Self.shared = self
        if let data = UserDefaults.standard.data(forKey: recentsKey),
           let saved = try? JSONDecoder().decode([RecentLibrary].self, from: data) {
            recents = saved
        }
        if let path = UserDefaults.standard.string(forKey: lastLibraryKey) {
            restoreLastLibrary(URL(fileURLWithPath: path))
        }
    }

    /// 资源库可能在“文稿”“桌面”这类受保护的文件夹里：第一次访问时系统弹出授权框，这次文件访问会一直等到用户点允许。
    /// 所以先在后台碰一下文件，主线程不被卡住，窗口能先显示出来。
    private func restoreLastLibrary(_ url: URL) {
        isRestoring = true
        Task {
            let exists = await Task.detached { LibraryStore.isLibrary(url) }.value
            if exists { open(url) }
            isRestoring = false
        }
    }

    // MARK: - 打开与关闭

    func open(_ url: URL) {
        do {
            let store = try LibraryStore.open(at: url)
            setLibrary(store)
        } catch {
            errorMessage = "无法打开资源库：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func create(at url: URL) -> LibraryStore? {
        let target = url.pathExtension == LibraryStore.fileExtension ? url : url.appendingPathExtension(LibraryStore.fileExtension)
        do {
            let store = try LibraryStore.create(at: target)
            setLibrary(store)
            return store
        } catch {
            errorMessage = "无法创建资源库：\(error.localizedDescription)"
            return nil
        }
    }

    func closeLibrary() {
        if let library { remember(library) }
        library = nil
        UserDefaults.standard.removeObject(forKey: lastLibraryKey)
    }

    private func setLibrary(_ store: LibraryStore) {
        if let library { remember(library) }
        library = store
        UserDefaults.standard.set(store.url.path, forKey: lastLibraryKey)
        remember(store)
    }

    // MARK: - 最近打开

    func remember(_ store: LibraryStore) {
        let counts = store.counts
        let entry = RecentLibrary(path: store.url.path, itemCount: counts.all, byteSize: counts.bytes, lastOpened: Date())
        recents.removeAll { $0.path == entry.path }
        recents.insert(entry, at: 0)
        recents = Array(recents.prefix(12))
        saveRecents()
    }

    func forget(_ recent: RecentLibrary) {
        recents.removeAll { $0.id == recent.id }
        saveRecents()
    }

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentsKey)
        }
    }

    // MARK: - 面板

    func showNewLibraryPanel() {
        guard let url = Panels.saveNewLibrary(suggestedName: "我的素材") else { return }
        create(at: url)
    }

    func showOpenLibraryPanel() {
        guard let url = Panels.chooseLibrary() else { return }
        if LibraryStore.isLibrary(url) {
            open(url)
        } else if EagleImporter.isEagleLibrary(url) {
            importEagle(from: url)
        } else {
            errorMessage = "“\(url.lastPathComponent)”不是 Kura 资源库。"
        }
    }

    func showEagleImportPanel() {
        guard let url = Panels.chooseEagleLibrary() else { return }
        importEagle(from: url)
    }

    /// 从 Eagle 迁移：新建一个资源库，再把素材、标签、文件夹、备注、评分复制过来
    func importEagle(from source: URL) {
        guard EagleImporter.isEagleLibrary(source) else {
            errorMessage = "“\(source.lastPathComponent)”不是 Eagle 资源库（缺少 metadata.json 或 images 文件夹）。"
            return
        }
        let suggested = source.deletingPathExtension().lastPathComponent
        guard let target = Panels.saveNewLibrary(suggestedName: suggested, title: "为导入的素材新建资源库") else { return }
        create(at: target)?.importEagleLibrary(source)
    }

    /// 欢迎页拖放：资源库直接打开，Eagle 资源库走迁移，普通文件夹新建资源库后导入
    func handleDrop(_ urls: [URL]) {
        guard let url = urls.first else { return }
        if LibraryStore.isLibrary(url) {
            open(url)
        } else if EagleImporter.isEagleLibrary(url) {
            importEagle(from: url)
        } else {
            guard let target = Panels.saveNewLibrary(suggestedName: url.deletingPathExtension().lastPathComponent) else { return }
            create(at: target)?.importFiles(urls)
        }
    }
}
