import Foundation

enum DashboardFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    static func previewText(for item: ClipboardItem) -> String {
        if item.isSecret {
            return "••••••••"
        }
        return item.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func typeSummary(for item: ClipboardItem) -> String {
        switch DashboardContentScope.inferredScope(for: item) {
        case .all:
            return "履歴"
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

    static func usageSummary(for item: ClipboardItem) -> String {
        item.usageCount > 0 ? "\(item.usageCount) 回" : "-"
    }

    static func captureSummary(for item: ClipboardItem) -> String {
        item.captureCount > 1 ? "\(item.captureCount) 回" : "-"
    }

    static func lastUsedSummary(for item: ClipboardItem) -> String {
        guard let lastUsedAt = item.lastUsedAt else { return "未使用" }
        return time.string(from: lastUsedAt)
    }

    @MainActor
    static func folderSummary(for item: ClipboardItem, manager: ClipboardManager) -> String {
        let folderIDs = manager.folderIDs(for: item)
        guard !folderIDs.isEmpty else { return "未整理" }
        let names = manager.folders
            .filter { folderIDs.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "フォルダ" : names.joined(separator: ", ")
    }
}

enum DashboardFrequentItems {
    static func orderedItems(from items: [ClipboardItem], limit: Int) -> [ClipboardItem] {
        Array(items
            .filter { $0.usageCount > 0 }
            .sorted(by: comesBefore)
            .prefix(limit))
    }

    private static func comesBefore(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.usageCount != rhs.usageCount {
            return lhs.usageCount > rhs.usageCount
        }

        let lhsLastUsed = lhs.lastUsedAt ?? .distantPast
        let rhsLastUsed = rhs.lastUsedAt ?? .distantPast
        if lhsLastUsed != rhsLastUsed {
            return lhsLastUsed > rhsLastUsed
        }

        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp > rhs.timestamp
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }
}
