import Foundation

enum DashboardContentScope: String, CaseIterable, Identifiable {
    case all
    case text
    case links
    case code
    case images
    case files
    case richContent
    case privateItems

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "すべて"
        case .text:
            return "テキスト"
        case .links:
            return "リンク"
        case .code:
            return "コード"
        case .images:
            return "画像"
        case .files:
            return "ファイル"
        case .richContent:
            return "リッチ"
        case .privateItems:
            return "非公開"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "tray.full"
        case .text:
            return "doc.text"
        case .links:
            return "link"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .images:
            return "photo"
        case .files:
            return "doc"
        case .richContent:
            return "textformat"
        case .privateItems:
            return "lock.fill"
        }
    }

    func filteredItems(from items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(matches)
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return !item.isSecret
                && item.primaryContentType == .plainText
                && !Self.isLikelyLink(item.content)
                && !Self.isLikelyCode(item.content)
        case .links:
            return !item.isSecret && (item.primaryContentType == .urlText || Self.isLikelyLink(item.content))
        case .code:
            return !item.isSecret && item.primaryContentType == .plainText && Self.isLikelyCode(item.content)
        case .images:
            return !item.isSecret && item.primaryContentType == .image
        case .files:
            return !item.isSecret && item.primaryContentType == .fileURL
        case .richContent:
            return !item.isSecret && [.rtf, .html].contains(item.primaryContentType)
        case .privateItems:
            return item.isSecret
        }
    }

    static func inferredScope(for item: ClipboardItem) -> DashboardContentScope {
        if item.isSecret {
            return .privateItems
        }
        switch item.primaryContentType {
        case .image:
            return .images
        case .fileURL:
            return .files
        case .rtf, .html:
            return .richContent
        case .urlText:
            return .links
        case .plainText, .unknown:
            break
        }
        if isLikelyLink(item.content) {
            return .links
        }
        if isLikelyCode(item.content) {
            return .code
        }
        return .text
    }

    private static func isLikelyLink(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("file://")
            || trimmed.hasPrefix("www.")
    }

    private static func isLikelyCode(_ content: String) -> Bool {
        let tokens = ["func ", "struct ", "class ", "enum ", "let ", "var ", "const ", "import ", "return ", "=>"]
        let lowercased = content.lowercased()
        let hasToken = tokens.contains { lowercased.contains($0) }
        let hasCodeShape = content.contains("{") && content.contains("}")
        return hasToken || hasCodeShape
    }
}
