import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum ItemKind: String, Sendable {
    case image, video, other

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "flv", "wmv", "mpg", "mpeg", "3gp", "ts", "mts", "m2ts",
    ]

    static func detect(fileExtension ext: String) -> ItemKind {
        let ext = ext.lowercased()
        if videoExtensions.contains(ext) { return .video }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return .other
    }
}

struct Item: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var ext: String
    var kind: ItemKind
    /// 相对资源库根目录的路径，例如 items/<id>/海报.jpg
    var path: String
    /// 相对资源库根目录的缩略图路径
    var thumb: String?
    var thumbRev: Int
    var size: Int64
    var width: Int
    var height: Int
    var duration: Double?
    var rating: Int
    var note: String
    var url: String
    var colors: [String]
    var tags: [String]
    var folderIDs: [String]
    var addedAt: Date
    var modifiedAt: Date
    var viewedAt: Date?
    var deletedAt: Date?
    /// 视频封面取自第几秒；nil 表示导入时自动取的那一帧
    var coverTime: Double? = nil
}

extension Item {
    /// 导入时自动取封面的位置，和 MediaProbe.video 保持一致
    var effectiveCoverTime: Double? {
        coverTime ?? duration.map { min($0 * 0.1, 3) }
    }
}

extension Item {
    var fileName: String { ext.isEmpty ? name : "\(name).\(ext)" }

    /// 网格里使用的宽高比，极端比例会被裁切
    var displayAspect: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return min(max(CGFloat(width) / CGFloat(height), 0.4), 3)
    }

    var dimensionText: String? {
        width > 0 && height > 0 ? "\(width) × \(height)" : nil
    }

    var metaLine: String {
        var parts: [String] = []
        if !ext.isEmpty { parts.append(ext.uppercased()) }
        if kind == .video, let duration {
            parts.append(Format.duration(duration))
        } else if let dimensionText {
            parts.append(dimensionText)
        }
        return parts.joined(separator: " · ")
    }
}

struct Folder: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var parentID: String?
    var color: String
    var sort: Int
}

struct LibraryCounts {
    var all = 0
    var uncategorized = 0
    var untagged = 0
    var recent = 0
    var trash = 0
    var bytes: Int64 = 0
    var folders: [String: Int] = [:]
    /// 包含子标签的素材，同一个素材只算一次
    var tags: [String: Int] = [:]
}

/// 标签自己的信息。素材上只记最具体的标签名，上下级关系记在这里
struct TagInfo: Equatable {
    var parent: String?
    /// 图标文件，相对资源库根目录
    var icon: String?
}
