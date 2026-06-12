import SwiftUI

struct DashboardView: View {
    let manager: ClipboardManager
    @ObservedObject private var historyState: ClipboardHistoryState
    @ObservedObject private var folderState: ClipboardFolderState
    @ObservedObject var settingsStore: AppSettingsStore
    let openSettings: () -> Void
    let openAbout: () -> Void

    @State private var selectedItemID: UUID?
    @State private var contentScope: DashboardContentScope = .all
    @State private var displayTitleEditingItem: ClipboardItem?

    init(
        manager: ClipboardManager,
        settingsStore: AppSettingsStore,
        openSettings: @escaping () -> Void,
        openAbout: @escaping () -> Void
    ) {
        self.manager = manager
        self.historyState = manager.historyState
        self.folderState = manager.folderState
        self.settingsStore = settingsStore
        self.openSettings = openSettings
        self.openAbout = openAbout
    }

    private var dashboardItems: [ClipboardItem] {
        contentScope.filteredItems(from: manager.visibleItems)
    }

    private var frequentDashboardItems: [ClipboardItem] {
        DashboardFrequentItems.orderedItems(from: dashboardItems, limit: 10)
    }

    private var selectedItem: ClipboardItem? {
        if let selectedItemID,
           let item = dashboardItems.first(where: { $0.id == selectedItemID }) {
            return item
        }
        return dashboardItems.first
    }

    private var selectedID: UUID? {
        selectedItem?.id
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .overlay(ForkclipTheme.dashboardBackground)

            HStack(spacing: 0) {
                DashboardSidebar(
                    manager: manager,
                    historyState: historyState,
                    folderState: folderState,
                    contentScope: $contentScope
                )

                Divider()
                    .background(ForkclipTheme.surfaceInk(0.08))

                VStack(spacing: 0) {
                    DashboardToolbar(
                        manager: manager,
                        historyState: historyState,
                        itemCount: dashboardItems.count,
                        openSettings: openSettings,
                        openAbout: openAbout
                    )

                    Divider()
                        .background(ForkclipTheme.surfaceInk(0.08))

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DashboardHighlightStrip(
                                manager: manager,
                                items: frequentDashboardItems,
                                selectedID: selectedID,
                                selectItem: selectItem,
                                copyItem: { item in Task { await manager.copyToClipboard(item) } },
                                editDisplayTitle: beginDisplayTitleEdit
                            )

                            Divider()
                                .background(ForkclipTheme.surfaceInk(0.08))

                            DashboardItemList(
                                manager: manager,
                                items: dashboardItems,
                                selectedID: selectedID,
                                selectItem: selectItem,
                                copyItem: { item in Task { await manager.copyToClipboard(item) } },
                                editDisplayTitle: beginDisplayTitleEdit
                            )
                        }

                        Divider()
                            .background(ForkclipTheme.surfaceInk(0.08))

                        DashboardInspector(
                            manager: manager,
                            item: selectedItem,
                            copyItem: { item in Task { await manager.copyToClipboard(item) } },
                            editDisplayTitle: beginDisplayTitleEdit
                        )
                    }
                }
            }
        }
        .onAppear {
            pruneSelection()
        }
        .onChange(of: dashboardItems.map(\.id)) { _ in
            pruneSelection()
        }
        .sheet(item: $displayTitleEditingItem) { item in
            DisplayTitleSheet(initialTitle: item.displayTitle ?? "") { title in
                Task { await manager.updateDisplayTitle(for: item, title: title) }
            }
        }
    }

    private func selectItem(_ item: ClipboardItem) {
        selectedItemID = item.id
    }

    private func beginDisplayTitleEdit(_ item: ClipboardItem) {
        selectedItemID = item.id
        displayTitleEditingItem = item
    }

    private func pruneSelection() {
        if let selectedItemID,
           dashboardItems.contains(where: { $0.id == selectedItemID }) {
            return
        }
        selectedItemID = dashboardItems.first?.id
    }
}
