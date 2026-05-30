import AppKit
import Foundation

struct ClipboardPayload: Equatable, Identifiable, @unchecked Sendable {
    let id: UUID
    let contentType: ClipboardContentType
    let pasteboardType: NSPasteboard.PasteboardType
    let data: Data
    let preview: String?
    let rank: Int

    var byteSize: Int {
        data.count
    }

    init(
        id: UUID = UUID(),
        contentType: ClipboardContentType,
        pasteboardType: NSPasteboard.PasteboardType,
        data: Data,
        preview: String? = nil,
        rank: Int
    ) {
        self.id = id
        self.contentType = contentType
        self.pasteboardType = pasteboardType
        self.data = data
        self.preview = preview
        self.rank = rank
    }

    static func plainText(_ text: String, rank: Int = 0) -> ClipboardPayload {
        ClipboardPayload(
            contentType: .plainText,
            pasteboardType: .string,
            data: Data(text.utf8),
            preview: nil,
            rank: rank
        )
    }
}
