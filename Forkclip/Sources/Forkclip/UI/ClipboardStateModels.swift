import SwiftUI
import Foundation
import AppKit

@MainActor
final class ClipboardHistoryState: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var queue: [ClipboardItem] = []
    @Published var isQueueMode: Bool = false
    @Published var isPrivateMode: Bool
    @Published var searchQuery: String = ""
    @Published var sourceAppFilter: String = ""
    @Published var isFavoritesOnly: Bool = false

    init(isPrivateMode: Bool = false) {
        self.isPrivateMode = isPrivateMode
    }
}

@MainActor
final class ClipboardFolderState: ObservableObject {
    @Published var folders: [ClipboardFolder] = []
    @Published var selectedFolder: HistoryFolderSelection = .all
    @Published var itemFolderIDs: [UUID: Set<UUID>] = [:]

    func folderIDs(for item: ClipboardItem) -> Set<UUID> {
        itemFolderIDs[item.id] ?? []
    }

    func folderName(for selection: HistoryFolderSelection) -> String {
        switch selection {
        case .all:
            return "すべて"
        case .unfiled:
            return "未整理"
        case .folder(let folderID):
            return folders.first(where: { $0.id == folderID })?.name ?? "フォルダ"
        }
    }
}

@MainActor
final class ClipboardSelectionState: ObservableObject {
    @Published var selectedItemIDs: Set<UUID> = []

    func isSelected(_ item: ClipboardItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggleSelection(for item: ClipboardItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }
}

@MainActor
final class ClipboardDiagnosticsState: ObservableObject {
    @Published var bannerStatus: ClipboardBannerStatus?
    @Published var diagnostics: DiagnosticsSnapshot
    @Published var isDiagnosticsPanelVisible: Bool = false
    @Published var recoveryStatus: ClipboardRecoveryStatus?
    @Published var folderStatus: ClipboardFolderStatus?

    init(diagnostics: DiagnosticsSnapshot = .initial()) {
        self.diagnostics = diagnostics
    }
}
