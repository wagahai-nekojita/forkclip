import CoreGraphics
import Foundation
import ImageIO

/// Resource limits shared by pasteboard capture, persistence, and thumbnail rendering.
/// The limits are intentionally small enough to keep clipboard ingestion bounded while
/// still allowing ordinary documents and screenshots.
enum ClipboardResourceLimits {
    static let maxPlainTextBytes = 1 * 1024 * 1024
    static let maxRichTextBytes = 4 * 1024 * 1024
    static let maxImageBytes = 16 * 1024 * 1024
    static let maxCaptureBytes = 20 * 1024 * 1024
    static let maxStoredPayloadBytes = 256 * 1024 * 1024
    static let maxImageDimension = 16_384
    static let maxImagePixelCount = 40_000_000
    static let thumbnailMaxPixelSize = 512
    static let maxThumbnailCacheEntries = 128

    static func maxBytes(for contentType: ClipboardContentType) -> Int {
        switch contentType {
        case .plainText, .urlText, .fileURL:
            return maxPlainTextBytes
        case .rtf, .html:
            return maxRichTextBytes
        case .image:
            return maxImageBytes
        case .unknown:
            return maxPlainTextBytes
        }
    }

    static func accepts(_ data: Data, for contentType: ClipboardContentType) -> Bool {
        guard data.count <= maxBytes(for: contentType) else {
            return false
        }
        guard contentType == .image else {
            return true
        }
        return !imageMetadataExceedsLimits(data)
    }

    static func accepts(_ text: String, for contentType: ClipboardContentType = .plainText) -> Bool {
        text.utf8.count <= maxBytes(for: contentType)
    }

    static func imageMetadataExceedsLimits(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else {
            // Preserve small, opaque pasteboard formats that ImageIO cannot inspect.
            // Thumbnail creation will fail closed if the bytes are not a real image.
            return false
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height, width > 0, height > 0 else {
            return false
        }
        guard width <= maxImageDimension, height <= maxImageDimension else {
            return true
        }
        return width > maxImagePixelCount / height
    }

    static func thumbnail(from data: Data) -> CGImage? {
        guard data.count <= maxImageBytes,
              !imageMetadataExceedsLimits(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
