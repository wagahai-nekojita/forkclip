import AppKit
import Foundation
import ImageIO

enum ImageThumbnailGenerator {
    static let maxPixelSize = 384

    static func thumbnail(from data: Data, maxPixelSize: Int = Self.maxPixelSize) -> NSImage? {
        guard ClipboardResourceLimits.accepts(data, for: .image) else {
            return nil
        }
        let sourceOptions = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let normalizedMaxPixelSize = max(1, maxPixelSize)
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: normalizedMaxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return NSImage(
            cgImage: thumbnail,
            size: NSSize(width: thumbnail.width, height: thumbnail.height)
        )
    }
}
