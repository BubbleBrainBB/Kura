import Foundation

/// 读取 Eagle 的 .library 资源库。只读，不会改动原资源库。
enum EagleImporter {
    struct FolderNode: Decodable {
        let id: String
        let name: String
        let children: [FolderNode]?
    }

    struct LibraryMetadata: Decodable {
        let folders: [FolderNode]?
    }

    struct ItemMetadata: Decodable {
        let name: String?
        let ext: String?
        let tags: [String]?
        let folders: [String]?
        let isDeleted: Bool?
        let url: String?
        let annotation: String?
        let star: Int?
        let btime: Double?
    }

    struct ScanResult {
        var folders: [FolderNode]
        var items: [(file: URL, metadata: ItemMetadata)]
    }

    static func isEagleLibrary(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("metadata.json").path)
            && fm.fileExists(atPath: url.appendingPathComponent("images").path)
    }

    static func scan(_ library: URL) throws -> ScanResult {
        let decoder = JSONDecoder()
        let fm = FileManager.default
        let libraryData = try Data(contentsOf: library.appendingPathComponent("metadata.json"))
        let folders = (try? decoder.decode(LibraryMetadata.self, from: libraryData))?.folders ?? []

        var items: [(URL, ItemMetadata)] = []
        let imagesDirectory = library.appendingPathComponent("images")
        let entries = try fm.contentsOfDirectory(at: imagesDirectory, includingPropertiesForKeys: nil)
        for entry in entries where entry.pathExtension == "info" {
            guard let data = try? Data(contentsOf: entry.appendingPathComponent("metadata.json")),
                  let metadata = try? decoder.decode(ItemMetadata.self, from: data),
                  metadata.isDeleted != true else { continue }
            if let file = originalFile(in: entry, metadata: metadata) {
                items.append((file, metadata))
            }
        }
        items.sort { ($0.1.btime ?? 0) < ($1.1.btime ?? 0) }
        return ScanResult(folders: folders, items: items)
    }

    private static func originalFile(in directory: URL, metadata: ItemMetadata) -> URL? {
        if let name = metadata.name, let ext = metadata.ext {
            let candidate = directory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first { file in
            let name = file.lastPathComponent
            return name != "metadata.json" && !name.contains("_thumbnail") && !name.hasPrefix(".")
        }
    }
}

extension LibraryStore {
    func importEagleLibrary(_ source: URL) {
        Task {
            let scanned = await Task.detached { try? EagleImporter.scan(source) }.value
            guard let scanned else {
                lastError = "读取 Eagle 资源库失败：\(source.lastPathComponent)"
                return
            }
            var folderMap: [String: String] = [:]
            @MainActor func createFolders(_ nodes: [EagleImporter.FolderNode], parentID: String?) {
                for node in nodes {
                    let folder = createFolder(named: node.name, parentID: parentID)
                    folderMap[node.id] = folder.id
                    createFolders(node.children ?? [], parentID: folder.id)
                }
            }
            createFolders(scanned.folders, parentID: nil)

            let jobs = scanned.items.map { entry in
                let meta = entry.metadata
                return ImportJob(
                    source: entry.file,
                    folderIDs: (meta.folders ?? []).compactMap { folderMap[$0] },
                    preset: ImportPreset(
                        name: meta.name,
                        tags: meta.tags ?? [],
                        note: meta.annotation ?? "",
                        url: meta.url ?? "",
                        rating: meta.star ?? 0,
                        addedAt: meta.btime.map { Date(timeIntervalSince1970: $0 / 1000) }
                    )
                )
            }
            enqueue(jobs)
        }
    }
}
