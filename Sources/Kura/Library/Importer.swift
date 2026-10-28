import Foundation

struct ImportProgress: Equatable {
    var total: Int
    var done: Int
    var failed: Int
}

/// 导入时预先填好的信息，用于从 Eagle 迁移
struct ImportPreset: Sendable {
    var name: String?
    var tags: [String] = []
    var note = ""
    var url = ""
    var rating = 0
    var addedAt: Date?
}

struct ImportJob: Sendable {
    var source: URL
    var folderIDs: [String] = []
    var preset: ImportPreset?
    /// 提前定好 id，粘贴完就能选中新素材
    var itemID = UUID().uuidString
}

extension LibraryStore {
    /// 导入拖进来、粘贴或选中的文件。文件夹会变成同名的资源库文件夹；本资源库里的文件只会被加进目标文件夹。
    /// 返回导入后的素材 id（含已经在库里的）
    @discardableResult
    func importFiles(_ urls: [URL], into folderID: String? = nil, tags: [String] = []) -> [String] {
        let preset = tags.isEmpty ? nil : ImportPreset(tags: tags)
        var jobs: [ImportJob] = []
        var existing: [String] = []
        for url in urls {
            if let item = item(atFileURL: url) {
                existing.append(item.id)
                continue
            }
            if contains(fileURL: url) || url.path == self.url.path { continue }
            if EagleImporter.isEagleLibrary(url) {
                importEagleLibrary(url)
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let folder = createFolder(named: url.lastPathComponent, parentID: folderID)
                jobs += Self.regularFiles(in: url).map { ImportJob(source: $0, folderIDs: [folder.id], preset: preset) }
            } else {
                jobs.append(ImportJob(source: url, folderIDs: folderID.map { [$0] } ?? [], preset: preset))
            }
        }
        if let folderID, !existing.isEmpty {
            addToFolder(existing, folderID)
        }
        if !existing.isEmpty {
            for tag in tags { addTagPath(existing, tag) }
        }
        enqueue(jobs)
        return existing + jobs.map(\.itemID)
    }

    nonisolated static func regularFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(url)
            }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// 并发处理（最多 4 个），分批写入数据库，避免界面频繁刷新
    func enqueue(_ jobs: [ImportJob]) {
        guard !jobs.isEmpty else { return }
        var progress = importProgress ?? ImportProgress(total: 0, done: 0, failed: 0)
        progress.total += jobs.count
        importProgress = progress
        activeImports += 1
        let libraryURL = url

        Task {
            var buffer: [Item] = []
            var lastFlush = Date()
            await withTaskGroup(of: Item?.self) { group in
                var pending = jobs.makeIterator()
                for _ in 0..<4 {
                    guard let job = pending.next() else { break }
                    group.addTask { await Self.prepare(job, libraryURL: libraryURL) }
                }
                for await result in group {
                    if let result { buffer.append(result) } else { importProgress?.failed += 1 }
                    importProgress?.done += 1
                    if buffer.count >= 24 || Date().timeIntervalSince(lastFlush) > 0.4 {
                        insert(buffer)
                        buffer.removeAll()
                        lastFlush = Date()
                    }
                    if let job = pending.next() {
                        group.addTask { await Self.prepare(job, libraryURL: libraryURL) }
                    }
                }
            }
            insert(buffer)
            activeImports -= 1
            if activeImports == 0 {
                let finished = importProgress
                try? await Task.sleep(for: .seconds(1.5))
                if activeImports == 0, importProgress == finished { importProgress = nil }
            }
        }
    }

    /// 复制文件、读取信息、生成缩略图和颜色。在后台线程运行。
    nonisolated static func prepare(_ job: ImportJob, libraryURL: URL) async -> Item? {
        let fm = FileManager.default
        let id = job.itemID
        let source = job.source
        let fileName = source.lastPathComponent
        let directory = libraryURL.appendingPathComponent("items/\(id)", isDirectory: true)
        let destination = directory.appendingPathComponent(fileName)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: destination)
        } catch {
            try? fm.removeItem(at: directory)
            return nil
        }

        let ext = source.pathExtension.lowercased()
        let kind = ItemKind.detect(fileExtension: ext)
        let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        let media = await MediaProbe.probe(destination, kind: kind)
        var thumb: String?
        var colors: [String] = []
        if let image = media.thumbnail {
            thumb = Thumbnailer.save(image, libraryURL: libraryURL, id: id)
            if !media.thumbnailIsIcon { colors = ColorExtractor.palette(of: image) }
        }

        let now = Date()
        let preset = job.preset
        return Item(
            id: id,
            name: preset?.name ?? source.deletingPathExtension().lastPathComponent,
            ext: ext,
            kind: kind,
            path: "items/\(id)/\(fileName)",
            thumb: thumb,
            thumbRev: 0,
            size: size,
            width: Int(media.size.width),
            height: Int(media.size.height),
            duration: media.duration,
            rating: preset?.rating ?? 0,
            note: preset?.note ?? "",
            url: preset?.url ?? "",
            colors: colors,
            tags: preset?.tags ?? [],
            folderIDs: job.folderIDs,
            addedAt: preset?.addedAt ?? now,
            modifiedAt: now,
            viewedAt: nil,
            deletedAt: nil
        )
    }
}
