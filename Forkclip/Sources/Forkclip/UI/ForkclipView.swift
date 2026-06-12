import SwiftUI

struct ForkclipView: View {
    let manager: ClipboardManager
    @ObservedObject private var historyState: ClipboardHistoryState
    @ObservedObject private var folderState: ClipboardFolderState
    @ObservedObject private var selectionState: ClipboardSelectionState
    @ObservedObject private var diagnosticsState: ClipboardDiagnosticsState
    @ObservedObject var settingsStore: AppSettingsStore
    let openDashboard: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void
    @State private var hoveredID: UUID?
    @State private var isNewFolderSheetVisible = false
    @State private var folderToRename: ClipboardFolder?

    init(
        manager: ClipboardManager,
        settingsStore: AppSettingsStore,
        openDashboard: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        openAbout: @escaping () -> Void
    ) {
        self.manager = manager
        self.historyState = manager.historyState
        self.folderState = manager.folderState
        self.selectionState = manager.selectionState
        self.diagnosticsState = manager.diagnosticsState
        self.settingsStore = settingsStore
        self.openDashboard = openDashboard
        self.openSettings = openSettings
        self.openAbout = openAbout
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(ForkclipTheme.quickPanelBackground)

            VStack(alignment: .leading, spacing: 0) {
                HistoryToolbar(
                    manager: manager,
                    historyState: historyState,
                    folderState: folderState,
                    selectionState: selectionState,
                    diagnosticsState: diagnosticsState,
                    settingsStore: settingsStore,
                    openDashboard: openDashboard,
                    openSettings: openSettings,
                    openAbout: openAbout,
                    onNewFolder: { isNewFolderSheetVisible = true },
                    onRenameFolder: { folderToRename = $0 }
                )

                statusMessages

                if diagnosticsState.isDiagnosticsPanelVisible {
                    DiagnosticsPanel(manager: manager, diagnosticsState: diagnosticsState)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }

                HistoryContent(
                    manager: manager,
                    historyState: historyState,
                    folderState: folderState,
                    layout: settingsStore.settings.historyLayout,
                    autoPasteOnCardSelection: settingsStore.settings.autoPasteOnCardSelection,
                    hoveredID: $hoveredID
                )
            }
        }
        .sheet(isPresented: $isNewFolderSheetVisible) {
            FolderNameSheet(title: "新しいフォルダ", initialName: "") { name in
                Task { _ = await manager.createFolder(named: name) }
            }
        }
        .sheet(item: $folderToRename) { folder in
            FolderNameSheet(title: "フォルダ名を変更", initialName: folder.name) { name in
                Task { _ = await manager.renameFolder(folder, to: name) }
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if let lockedStatus = LockedHistoryUX.status(for: diagnosticsState.diagnostics) {
            LockedHistoryBanner(status: lockedStatus) {
                diagnosticsState.isDiagnosticsPanelVisible = true
                Task { await manager.refreshDiagnostics() }
            }
        } else if let bannerStatus = diagnosticsState.bannerStatus {
            StatusBanner(systemImage: "exclamationmark.triangle.fill", text: ClipboardStatusFormatter.bannerText(bannerStatus), color: .orange)
        }

        if let recoveryStatus = diagnosticsState.recoveryStatus {
            StatusBanner(systemImage: "wrench.and.screwdriver.fill", text: ClipboardStatusFormatter.recoveryText(recoveryStatus), color: .green)
        }

        if let folderStatus = diagnosticsState.folderStatus {
            StatusBanner(systemImage: "folder.badge.questionmark", text: ClipboardStatusFormatter.folderText(folderStatus), color: .blue)
        }
    }
}
