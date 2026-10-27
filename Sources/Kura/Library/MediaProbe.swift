import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

struct MediaInfo {
    var size: CGSize = .zero
    var duration: Double?
    var thumbnail: CGImage?
    /// 缩略图只是文件类型图标（系统认不出内容时）
    var thumbnailIsIcon = false
}

/// 读取尺寸、时长，并生成缩略图。图片走 ImageIO，视频走 AVFoundation，其余交给 Quick Look。
enum MediaProbe {
    static func probe(_ url: URL, kind: ItemKind) async -> MediaInfo {
        var info: MediaInfo
        switch kind {
        case .image: info = image(url)
        case .video: info = await video(url)
        case .other: info = MediaInfo()
        }
        if info.thumbnail == nil, let preview = await quickLookThumbnail(url) {
            info.thumbnail = preview.image
            info.thumbnailIsIcon = preview.isIcon
            // 只拿到文件类型图标时，图标尺寸不能当作素材尺寸
            if info.size == .zero, kind != .other, !preview.isIcon {
                info.size = CGSize(width: preview.image.width, height: preview.image.height)
            }
        }
        return info
    }

    static func image(_ url: URL) -> MediaInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return MediaInfo() }
        var info = MediaInfo()
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            // EXIF 方向 5–8 表示旋转了 90°
            info.size = orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Thumbnailer.maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        info.thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        if info.size == .zero, let thumbnail = info.thumbnail {
            info.size = CGSize(width: thumbnail.width, height: thumbnail.height)
        }
        return info
    }

    static func video(_ url: URL) async -> MediaInfo {
        let asset = AVURLAsset(url: url)
        var info = MediaInfo()
        if let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 {
            info.duration = duration.seconds
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            info.size = CGSize(width: abs(rect.width).rounded(), height: abs(rect.height).rounded())
        }
        let posterTime = min((info.duration ?? 0) * 0.1, 3)
        info.thumbnail = try? await frame(of: asset, at: posterTime)
        return info
    }

    static func videoFrame(_ url: URL, at seconds: Double) async throws -> CGImage {
        try await frame(of: AVURLAsset(url: url), at: seconds)
    }

    private static func frame(of asset: AVAsset, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Thumbnailer.maxPixelSize, height: Thumbnailer.maxPixelSize)
        let tolerance = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    static func quickLookThumbnail(_ url: URL) async -> (image: CGImage, isIcon: Bool)? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 360, height: 360),
            scale: 2,
            representationTypes: .all
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return (representation.cgImage, representation.type == .icon)
    }
}

enum Thumbnailer {
    static let maxPixelSize = 720

    /// 保存缩略图，返回相对资源库的路径。带透明通道的存 PNG，其余存 JPEG。
    static func save(_ image: CGImage, libraryURL: URL, id: String) -> String? {
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let ext = hasAlpha ? "png" : "jpg"
        let relative = "thumbs/\(id).\(ext)"
        let directory = libraryURL.appendingPathComponent("thumbs")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 换了格式时清掉旧文件
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).\(hasAlpha ? "jpg" : "png")"))
        let destinationURL = libraryURL.appendingPathComponent(relative)
        let type = (hasAlpha ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? relative : nil
    }
}

enum ColorExtractor {
    /// 缩到 32×32 后按 4 位量化统计，取出现最多且彼此差异明显的几种颜色
    static func palette(of image: CGImage, count: Int = 5) -> [String] {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        struct Bucket { var count = 0, r = 0, g = 0, b = 0 }
        var buckets: [Int: Bucket] = [:]
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            guard alpha >= 128 else { continue }
            let r = min(255, Int(pixels[i]) * 255 / alpha)
            let g = min(255, Int(pixels[i + 1]) * 255 / alpha)
            let b = min(255, Int(pixels[i + 2]) * 255 / alpha)
            let key = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4)
            var bucket = buckets[key, default: Bucket()]
            bucket.count += 1
            bucket.r += r
            bucket.g += g
            bucket.b += b
            buckets[key] = bucket
        }

        var picked: [(Int, Int, Int)] = []
        for bucket in buckets.values.sorted(by: { $0.count > $1.count }) {
            let color = (bucket.r / bucket.count, bucket.g / bucket.count, bucket.b / bucket.count)
            let distinct = picked.allSatisfy { other in
                let dr = color.0 - other.0, dg = color.1 - other.1, db = color.2 - other.2
                return dr * dr + dg * dg + db * db > 48 * 48
            }
            if distinct { picked.append(color) }
            if picked.count == count { break }
        }
        return picked.map { String(format: "#%02X%02X%02X", $0.0, $0.1, $0.2) }
    }
}
