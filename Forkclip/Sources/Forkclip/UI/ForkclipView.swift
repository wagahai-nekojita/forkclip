import SwiftUI
import AppKit

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

struct HistoryToolbar: View {
    let manager: ClipboardManager
    @ObservedObject var historyState: ClipboardHistoryState
    @ObservedObject var folderState: ClipboardFolderState
    @ObservedObject var selectionState: ClipboardSelectionState
    @ObservedObject var diagnosticsState: ClipboardDiagnosticsState
    @ObservedObject var settingsStore: AppSettingsStore
    let openDashboard: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void
    let onNewFolder: () -> Void
    let onRenameFolder: (ClipboardFolder) -> Void
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                searchField

                FolderChipBar(
                    manager: manager,
                    historyState: historyState,
                    folderState: folderState,
                    onNewFolder: onNewFolder,
                    onRenameFolder: onRenameFolder
                )
                .layoutPriority(1)

                Spacer(minLength: 12)

                activeStateChips

                QuickPanelOverflowMenu(
                    manager: manager,
                    historyState: historyState,
                    diagnosticsState: diagnosticsState,
                    settingsStore: settingsStore,
                    openDashboard: openDashboard,
                    openSettings: openSettings,
                    openAbout: openAbout
                )
                .layoutPriority(2)
                .fixedSize(horizontal: true, vertical: false)
            }

            selectedActions
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(ForkclipTheme.surfaceShade(0.18))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ForkclipTheme.separator(0.10))
                .frame(height: 1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(ForkclipTheme.ink(0.58))
            TextField("履歴を検索", text: $historyState.searchQuery)
                .textFieldStyle(.plain)
                .foregroundColor(ForkclipTheme.ink())
                .focused($isSearchFocused)
                .accessibilityLabel("履歴を検索")
            if !historyState.searchQuery.isEmpty {
                Button {
                    historyState.searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ForkclipTheme.ink(0.52))
                }
                .buttonStyle(.plain)
                .help("検索をクリア")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: 260)
        .background(ForkclipTheme.surfaceInk(0.085))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSearchFocused ? Color.accentColor.opacity(0.70) : ForkclipTheme.separator(0.11), lineWidth: isSearchFocused ? 1.5 : 1)
        )
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private var activeStateChips: some View {
        if !historyState.sourceAppFilter.isEmpty {
            QuickPanelChip(
                title: manager.sourceAppDisplayName(for: historyState.sourceAppFilter),
                systemImage: "app.dashed",
                isSelected: true
            ) {
                historyState.sourceAppFilter = ""
            }
            .help("アプリ絞り込みを解除")
        }

        if !historyState.queue.isEmpty {
            queueStatus
        }

        if settingsStore.settings.autoPasteOnCardSelection {
            QuickPanelChip(
                title: "クリックで貼り付け",
                systemImage: "command",
                isSelected: true
            ) {
                settingsStore.settings.autoPasteOnCardSelection = false
                _ = settingsStore.save()
            }
            .help("Auto Paste ON。Clipboard Item のクリックでコピー後に直前のアプリへ貼り付けを試みます。クリックでOFF。")
        }

        if historyState.isPrivateMode {
            QuickPanelChip(title: "非公開", systemImage: "eye.slash", isSelected: true) {
                historyState.isPrivateMode = false
            }
            .help("非公開をOFF")
        }
    }

    @ViewBuilder
    private var selectedActions: some View {
        if !selectionState.selectedItemIDs.isEmpty {
            HStack(spacing: 8) {
                Text("選択 \(selectionState.selectedItemIDs.count)")
                    .font(.caption.bold())
                    .foregroundColor(ForkclipTheme.ink(0.88))

                Menu("移動") {
                    Button("未整理") { Task { await manager.unassignSelectedItemsFromAllFolders() } }
                    if !folderState.folders.isEmpty {
                        Divider()
                    }
                    ForEach(folderState.folders) { folder in
                        Button(folder.name) { Task { await manager.assignSelectedItems(to: folder) } }
                    }
                }

                Button("削除") { Task { await manager.deleteSelectedItems() } }
                    .foregroundColor(.red)
                Button("解除") { selectionState.clearSelection() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(ForkclipTheme.surfaceInk(0.075))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ForkclipTheme.surfaceInk(0.10), lineWidth: 1)
            )
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private var queueStatus: some View {
        if !historyState.queue.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.system(size: 10, weight: .bold))
                Text("\(historyState.queue.count)")
                    .font(.caption.bold())
                Button {
                    historyState.queue.removeAll()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("キューをクリア")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundColor(ForkclipTheme.ink(0.92))
            .background(Color.accentColor.opacity(0.30))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor.opacity(0.42), lineWidth: 1)
            )
            .cornerRadius(9)
        }
    }
}

private struct FolderChipBar: View {
    let manager: ClipboardManager
    @ObservedObject var historyState: ClipboardHistoryState
    @ObservedObject var folderState: ClipboardFolderState
    let onNewFolder: () -> Void
    let onRenameFolder: (ClipboardFolder) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                QuickPanelChip(
                    title: "すべて",
                    systemImage: "tray.full",
                    isSelected: folderState.selectedFolder == .all
                ) {
                    folderState.selectedFolder = .all
                }

                QuickPanelChip(
                    title: "未整理",
                    systemImage: "tray",
                    isSelected: folderState.selectedFolder == .unfiled
                ) {
                    folderState.selectedFolder = .unfiled
                }

                ForEach(folderState.folders) { folder in
                    QuickPanelChip(
                        title: folder.name,
                        systemImage: "folder",
                        isSelected: folderState.selectedFolder == .folder(folder.id)
                    ) {
                        folderState.selectedFolder = .folder(folder.id)
                    }
                    .contextMenu {
                        Button("名前を変更") { onRenameFolder(folder) }
                        Button("上へ移動") { Task { await manager.moveFolder(folder, direction: -1) } }
                        Button("下へ移動") { Task { await manager.moveFolder(folder, direction: 1) } }
                        Divider()
                        Button("削除", role: .destructive) { Task { await manager.deleteFolder(folder) } }
                    }
                }

                QuickPanelIconChip(systemImage: "plus", help: "フォルダを追加", action: onNewFolder)
                FavoriteFilterButton(historyState: historyState)
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct QuickPanelChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(ForkclipTheme.ink(isSelected ? 0.96 : 0.72))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(isSelected ? ForkclipTheme.surfaceInk(0.13) : ForkclipTheme.surfaceInk(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? ForkclipTheme.surfaceInk(0.20) : ForkclipTheme.surfaceInk(0.065), lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }
}

private struct QuickPanelIconChip: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .foregroundColor(ForkclipTheme.ink(0.70))
                .background(ForkclipTheme.surfaceInk(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(ForkclipTheme.surfaceInk(0.065), lineWidth: 1)
                )
                .cornerRadius(9)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct QuickPanelOverflowMenu: View {
    let manager: ClipboardManager
    @ObservedObject var historyState: ClipboardHistoryState
    @ObservedObject var diagnosticsState: ClipboardDiagnosticsState
    @ObservedObject var settingsStore: AppSettingsStore
    let openDashboard: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void

    var body: some View {
        Menu {
            Button("Dashboard を開く", action: openDashboard)
            Button(diagnosticsState.isDiagnosticsPanelVisible ? "診断を閉じる" : "診断を開く") {
                diagnosticsState.isDiagnosticsPanelVisible.toggle()
                Task { await manager.refreshDiagnostics() }
            }
            Button("設定", action: openSettings)
            Button("\(AppInfo.displayName) について", action: openAbout)

            Divider()

            Menu("表示") {
                ForEach(HistoryLayout.allCases) { layout in
                    Button(layoutTitle(for: layout)) {
                        settingsStore.settings.historyLayout = layout
                        _ = settingsStore.save()
                    }
                }
            }

            Menu("アプリ") {
                Button(sourceTitle("すべて", isSelected: historyState.sourceAppFilter.isEmpty)) {
                    historyState.sourceAppFilter = ""
                }
                ForEach(manager.sourceBundleIDs, id: \.self) { bundleID in
                    Button(sourceTitle(manager.sourceAppDisplayName(for: bundleID), isSelected: historyState.sourceAppFilter == bundleID)) {
                        historyState.sourceAppFilter = bundleID
                    }
                }
            }

            Button(historyState.isFavoritesOnly ? "お気に入りを解除" : "お気に入りのみ表示") {
                historyState.isFavoritesOnly.toggle()
            }
            Button(historyState.isPrivateMode ? "非公開をOFF" : "非公開をON") {
                historyState.isPrivateMode.toggle()
            }
            Button(historyState.isQueueMode ? "キューをOFF" : "キューをON") {
                historyState.isQueueMode.toggle()
            }
            if !historyState.queue.isEmpty {
                Button("キューをクリア") {
                    historyState.queue.removeAll()
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                Text("操作")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(minWidth: 62, minHeight: 30)
            .padding(.horizontal, 8)
            .foregroundColor(ForkclipTheme.ink(0.78))
            .background(ForkclipTheme.surfaceInk(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(ForkclipTheme.surfaceInk(0.085), lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .help("操作メニュー")
        .accessibilityLabel("操作メニュー")
    }

    private func layoutTitle(for layout: HistoryLayout) -> String {
        "\(settingsStore.settings.historyLayout == layout ? "✓ " : "")\(localizedName(for: layout))"
    }

    private func sourceTitle(_ title: String, isSelected: Bool) -> String {
        "\(isSelected ? "✓ " : "")\(title)"
    }

    private func localizedName(for layout: HistoryLayout) -> String {
        switch layout {
        case .horizontal:
            return "横スクロール"
        case .grid:
            return "グリッド"
        case .list:
            return "リスト"
        }
    }
}

private struct PanelControlShell<Content: View>: View {
    let systemImage: String
    let content: Content

    init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ForkclipTheme.ink(0.56))
                .frame(width: 14)
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(ForkclipTheme.surfaceInk(0.060))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(ForkclipTheme.surfaceInk(0.085), lineWidth: 1)
        )
        .cornerRadius(9)
    }
}

private struct QueueOverflowMenu: View {
    @ObservedObject var manager: ClipboardManager

    var body: some View {
        Menu {
            Button(manager.isQueueMode ? "キューをOFF" : "キューをON") {
                manager.isQueueMode.toggle()
            }
            if !manager.queue.isEmpty {
                Divider()
                Button("キューをクリア") {
                    manager.queue.removeAll()
                }
            }
        } label: {
            Image(systemName: manager.isQueueMode ? "text.line.first.and.arrowtriangle.forward.circle.fill" : "ellipsis.circle")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundColor(manager.isQueueMode ? .accentColor : ForkclipTheme.ink(0.78))
                .background(ForkclipTheme.surfaceInk(manager.isQueueMode ? 0.11 : 0.060))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(manager.isQueueMode ? Color.accentColor.opacity(0.36) : ForkclipTheme.surfaceInk(0.08), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
        .help("キューと追加操作")
    }
}

private struct PrivateModeChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text("非公開")
                    .font(.caption.weight(.semibold))
                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(isOn ? Color.accentColor.opacity(0.55) : ForkclipTheme.surfaceInk(0.08))
                    .cornerRadius(5)
            }
            .foregroundColor(ForkclipTheme.ink(isOn ? 0.96 : 0.78))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isOn ? Color.accentColor.opacity(0.24) : ForkclipTheme.surfaceInk(0.060))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isOn ? Color.accentColor.opacity(0.44) : ForkclipTheme.surfaceInk(0.085), lineWidth: 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
        .help("ON中は新規履歴を保存しない")
        .accessibilityLabel("非公開")
        .accessibilityValue(isOn ? "ON" : "OFF")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct ModeSwitch: View {
    let title: String
    let activeTitle: String
    let systemImage: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .toggleStyle(
            ModeSwitchToggleStyle(
                title: title,
                systemImage: systemImage
            )
        )
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? activeTitle : "OFF")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct ModeSwitchToggleStyle: ToggleStyle {
    let title: String
    let systemImage: String

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(configuration.isOn ? .accentColor : ForkclipTheme.ink(0.7))
                    .frame(width: 14)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ForkclipTheme.ink(configuration.isOn ? 0.96 : 0.78))

                Text(configuration.isOn ? "ON" : "OFF")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(configuration.isOn ? .white : ForkclipTheme.ink(0.52))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(configuration.isOn ? Color.accentColor.opacity(0.55) : ForkclipTheme.surfaceInk(0.08))
                    .cornerRadius(5)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(configuration.isOn ? Color.accentColor.opacity(0.22) : ForkclipTheme.surfaceInk(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(configuration.isOn ? Color.accentColor.opacity(0.45) : ForkclipTheme.surfaceInk(0.08), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

struct ToolbarIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(ForkclipTheme.surfaceInk(0.060))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ForkclipTheme.surfaceInk(0.08), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .foregroundColor(ForkclipTheme.ink(0.86))
        .help(help)
    }
}

struct FolderFilterMenu: View {
    @ObservedObject var manager: ClipboardManager

    var body: some View {
        Menu {
            Button("すべて") { manager.selectedFolder = .all }
            Button("未整理") { manager.selectedFolder = .unfiled }
            if !manager.folders.isEmpty {
                Divider()
            }
            ForEach(manager.folders) { folder in
                Button(folder.name) { manager.selectedFolder = .folder(folder.id) }
            }
        } label: {
            Text(manager.folderName(for: manager.selectedFolder))
                .lineLimit(1)
                .font(.caption.weight(.semibold))
                .foregroundColor(ForkclipTheme.ink(0.82))
        }
        .menuStyle(.borderlessButton)
        .help("フォルダで絞り込み")
    }
}

struct FavoriteFilterButton: View {
    @ObservedObject var historyState: ClipboardHistoryState

    var body: some View {
        QuickPanelChip(
            title: "お気に入り",
            systemImage: historyState.isFavoritesOnly ? "star.fill" : "star",
            isSelected: historyState.isFavoritesOnly
        ) {
            historyState.isFavoritesOnly.toggle()
        }
        .help(historyState.isFavoritesOnly ? "お気に入りフィルタを解除" : "お気に入りだけ表示")
        .accessibilityLabel("お気に入り")
        .accessibilityValue(historyState.isFavoritesOnly ? "ON" : "OFF")
    }
}

struct FolderSidebar: View {
    @ObservedObject var manager: ClipboardManager
    let onNewFolder: () -> Void
    let onRenameFolder: (ClipboardFolder) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("フォルダ")
                    .font(.caption.bold())
                    .foregroundColor(ForkclipTheme.ink(0.62))
                Spacer()
                Button(action: onNewFolder) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(ForkclipTheme.surfaceInk(0.075))
                        .cornerRadius(7)
                }
                .buttonStyle(.plain)
                .foregroundColor(ForkclipTheme.ink(0.84))
                .help("フォルダを追加")
            }

            FolderSelectionButton(
                title: "すべて",
                systemImage: "tray.full",
                isSelected: manager.selectedFolder == .all
            ) {
                manager.selectedFolder = .all
            }

            FolderSelectionButton(
                title: "未整理",
                systemImage: "tray",
                isSelected: manager.selectedFolder == .unfiled
            ) {
                manager.selectedFolder = .unfiled
            }

            Divider()
                .background(ForkclipTheme.surfaceInk(0.08))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(manager.folders) { folder in
                        FolderSelectionButton(
                            title: folder.name,
                            systemImage: "folder",
                            isSelected: manager.selectedFolder == .folder(folder.id)
                        ) {
                            manager.selectedFolder = .folder(folder.id)
                        }
                        .contextMenu {
                            Button("名前を変更") { onRenameFolder(folder) }
                            Button("上へ移動") { Task { await manager.moveFolder(folder, direction: -1) } }
                            Button("下へ移動") { Task { await manager.moveFolder(folder, direction: 1) } }
                            Divider()
                            Button("削除", role: .destructive) { Task { await manager.deleteFolder(folder) } }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 180)
        .background(
            LinearGradient(
                colors: [
                    ForkclipTheme.surfaceShade(0.24),
                    ForkclipTheme.surfaceInk(0.025)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct FolderSelectionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                Text(title)
                    .lineLimit(1)
                Spacer()
            }
            .font(.caption)
            .foregroundColor(ForkclipTheme.ink(isSelected ? 0.96 : 0.74))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.34) : ForkclipTheme.surfaceInk(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.36) : ForkclipTheme.surfaceInk(0.04), lineWidth: 1)
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

struct HistoryContent: View {
    let manager: ClipboardManager
    @ObservedObject var historyState: ClipboardHistoryState
    @ObservedObject var folderState: ClipboardFolderState
    let layout: HistoryLayout
    let autoPasteOnCardSelection: Bool
    @Binding var hoveredID: UUID?

    private let columns = [
        GridItem(.adaptive(minimum: CompactHistoryCardMetrics.gridMinWidth, maximum: CompactHistoryCardMetrics.gridMaxWidth), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if historyState.items.isEmpty {
                EmptyHistoryView(
                    title: "履歴はまだありません",
                    message: "コピーしたテキストはここに表示されます。"
                )
            } else if manager.visibleItems.isEmpty {
                EmptyHistoryView(
                    title: "一致する履歴がありません",
                    message: "検索、アプリ、フォルダの条件を見直してください。"
                )
            } else {
                historyList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var historyList: some View {
        if layout == .horizontal {
            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(manager.visibleItems) { item in
                        HistoryItemCard(
                            item: item,
                            manager: manager,
                            hoveredID: $hoveredID,
                            autoPasteOnCardSelection: autoPasteOnCardSelection
                        )
                            .frame(width: CompactHistoryCardMetrics.horizontalWidth, height: CompactHistoryCardMetrics.cardHeight)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .fixedSize(horizontal: true, vertical: false)
                .background(HorizontalWheelScrollBridge())
            }
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                if layout == .grid {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(manager.visibleItems) { item in
                            HistoryItemCard(
                                item: item,
                                manager: manager,
                                hoveredID: $hoveredID,
                                autoPasteOnCardSelection: autoPasteOnCardSelection
                            )
                                .frame(height: CompactHistoryCardMetrics.cardHeight)
                        }
                    }
                    .padding(18)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(manager.visibleItems) { item in
                            HistoryItemRow(
                                item: item,
                                manager: manager,
                                hoveredID: $hoveredID,
                                autoPasteOnCardSelection: autoPasteOnCardSelection
                            )
                        }
                    }
                    .padding(18)
                }
            }
        }
    }
}

private enum CompactHistoryCardMetrics {
    static let horizontalWidth: CGFloat = 280
    static let cardHeight: CGFloat = 158
    static let gridMinWidth: CGFloat = 240
    static let gridMaxWidth: CGFloat = 300
    static let listRowHeight: CGFloat = 96
}

struct EmptyHistoryView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 30))
                .foregroundColor(ForkclipTheme.ink(0.45))
            Text(title)
                .font(.headline)
                .foregroundColor(ForkclipTheme.ink())
            Text(message)
                .font(.caption)
                .foregroundColor(ForkclipTheme.ink(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(ForkclipTheme.surfaceInk(0.018))
    }
}

struct HistoryItemCard: View {
    let item: ClipboardItem
    @ObservedObject var manager: ClipboardManager
    @Binding var hoveredID: UUID?
    @State private var isDisplayTitleEditorPresented = false
    var autoPasteOnCardSelection = false
    var cardHeight: CGFloat = CompactHistoryCardMetrics.cardHeight

    var body: some View {
        ClipboardCard(
            item: item,
            thumbnail: manager.imageThumbnail(for: item),
            isHovered: hoveredID == item.id,
            isSelected: manager.isSelected(item),
            cardHeight: cardHeight,
            clickAction: clickAction
        )
            .onHover { hovering in hoveredID = hovering ? item.id : nil }
            .onTapGesture { copyOrQueue() }
            .help(clickAction.help)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 1) {
                    Button {
                        Task { await manager.toggleFavorite(for: item) }
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundColor(item.isFavorite ? .yellow : ForkclipTheme.ink(0.72))
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(item.isFavorite ? "お気に入りを解除" : "お気に入りに追加")
                    .accessibilityLabel(item.isFavorite ? "お気に入りを解除" : "お気に入りに追加")

                    Button {
                        manager.toggleSelection(for: item)
                    } label: {
                        Image(systemName: manager.isSelected(item) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(manager.isSelected(item) ? .accentColor : ForkclipTheme.ink(0.72))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(manager.isSelected(item) ? "選択を解除" : "選択")
                }
                .background(ForkclipTheme.surfaceShade(0.28))
                .cornerRadius(8)
                .padding(8)
            }
            .contextMenu { itemContextMenu }
            .sheet(isPresented: $isDisplayTitleEditorPresented) {
                DisplayTitleSheet(initialTitle: item.displayTitle ?? "") { title in
                    Task { await manager.updateDisplayTitle(for: item, title: title) }
                }
            }
    }

    @ViewBuilder
    private var itemContextMenu: some View {
        Button(manager.isSelected(item) ? "選択を解除" : "選択") { manager.toggleSelection(for: item) }
        Button(item.isFavorite ? "お気に入りを解除" : "お気に入りに追加") { Task { await manager.toggleFavorite(for: item) } }
        Button("表示名を編集…") { isDisplayTitleEditorPresented = true }
        Divider()
        Button("キューに追加") { manager.addToQueue(item) }
        Button("プレーンテキストとしてコピー") {
            Task { await manager.copyPlainTextToClipboard(from: item) }
        }
        folderMenu
        Divider()
        Button("削除", role: .destructive) { Task { await manager.delete(item) } }
    }

    @ViewBuilder
    private var folderMenu: some View {
        Menu("フォルダへ移動") {
            Button("未整理") { Task { await manager.unassignFromAllFolders(item) } }
            if !manager.folders.isEmpty {
                Divider()
            }
            ForEach(manager.folders) { folder in
                Button(folder.name) { Task { await manager.assign(item, to: folder) } }
            }
        }
    }

    private func copyOrQueue() {
        if manager.isQueueMode {
            manager.addToQueue(item)
        } else {
            Task { await manager.copyToClipboard(item, autoPaste: autoPasteOnCardSelection) }
        }
    }

    private var clickAction: ClipboardCardClickAction {
        if manager.isQueueMode {
            return ClipboardCardClickAction(
                title: "クリックでキュー",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                help: "クリックするとこの Clipboard Item をキューに追加します。"
            )
        }
        if autoPasteOnCardSelection {
            return ClipboardCardClickAction(
                title: "クリックで貼り付け",
                systemImage: "command",
                help: "クリックするとコピー後、直前のアプリへ貼り付けを試みます。"
            )
        }
        return ClipboardCardClickAction(
            title: "クリックでコピー",
            systemImage: "doc.on.clipboard",
            help: "クリックするとこの Clipboard Item をクリップボードへコピーします。"
        )
    }
}

struct HistoryItemRow: View {
    let item: ClipboardItem
    @ObservedObject var manager: ClipboardManager
    @Binding var hoveredID: UUID?
    var autoPasteOnCardSelection = false

    var body: some View {
        HistoryItemCard(
            item: item,
            manager: manager,
            hoveredID: $hoveredID,
            autoPasteOnCardSelection: autoPasteOnCardSelection,
            cardHeight: CompactHistoryCardMetrics.listRowHeight
        )
        .frame(height: CompactHistoryCardMetrics.listRowHeight)
        .frame(maxWidth: .infinity)
    }
}

struct DiagnosticsPanel: View {
    let manager: ClipboardManager
    @ObservedObject var diagnosticsState: ClipboardDiagnosticsState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("診断パネル")
                    .font(.caption.bold())
                    .foregroundColor(ForkclipTheme.ink())
                Spacer()
                Text("\(AppInfo.displayName) \(AppInfo.versionDisplay)")
                    .font(.caption2)
                    .foregroundColor(ForkclipTheme.ink(0.55))
            }

            DiagnosticRow(label: "データベースパス", value: ClipboardStatusFormatter.databasePathText(diagnosticsState.diagnostics.databasePath))
            DiagnosticRow(label: "データベース状態", value: ClipboardStatusFormatter.databaseText(diagnosticsState.diagnostics.databaseStatus))
            DiagnosticRow(label: "Keychain 状態", value: ClipboardStatusFormatter.keyText(diagnosticsState.diagnostics.keyState))
            DiagnosticRow(label: "監視状態", value: ClipboardStatusFormatter.monitorText(diagnosticsState.diagnostics.monitorState))
            DiagnosticRow(label: "最終変更番号", value: ClipboardStatusFormatter.changeCountText(diagnosticsState.diagnostics.lastObservedChangeCount))
            DiagnosticRow(
                label: "最終処理時刻",
                value: ClipboardStatusFormatter.diagnosticsProcessedAtText(diagnosticsState.diagnostics.lastProcessedChangeAt)
            )
            DiagnosticRow(label: "保存結果", value: ClipboardStatusFormatter.operationText(diagnosticsState.diagnostics.lastSaveStatus))
            DiagnosticRow(label: "保存エラー詳細", value: diagnosticsState.diagnostics.lastSaveError ?? "なし")
            DiagnosticRow(label: "復号できない履歴", value: "\(diagnosticsState.diagnostics.fetchFailureCount) 件")
            DiagnosticRow(label: "最新セキュリティエラー", value: diagnosticsState.diagnostics.securityErrorDescription ?? "なし")
            DiagnosticRow(label: "復旧用バックアップ", value: diagnosticsState.diagnostics.lastRecoveryBackupPath ?? "未作成")

            if diagnosticsState.diagnostics.keyState == .missing || diagnosticsState.diagnostics.fetchFailureCount > 0 {
                HStack(spacing: 12) {
                    Button("バックアップして初期化") {
                        Task { await manager.recoverFromMissingKey() }
                    }
                    .buttonStyle(.borderedProminent)

                    Text("既存 DB をバックアップし、新しい暗号鍵で履歴 DB を初期化します。")
                        .font(.caption2)
                        .foregroundColor(ForkclipTheme.ink(0.8))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ForkclipTheme.surfaceShade(0.24))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ForkclipTheme.surfaceInk(0.08), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(ForkclipTheme.ink(0.6))
            Text(value)
                .font(.caption)
                .foregroundColor(ForkclipTheme.ink())
                .textSelection(.enabled)
        }
    }
}

struct ClipboardCard: View {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let isHovered: Bool
    let isSelected: Bool
    let cardHeight: CGFloat
    let clickAction: ClipboardCardClickAction

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                metadataBadge(
                    title: item.bundleID?.components(separatedBy: ".").last?.uppercased() ?? "TEXT",
                    systemImage: "app.dashed",
                    color: .accentColor
                )
                if item.isSecret {
                    metadataBadge(title: "Private", systemImage: "lock.fill", color: .orange)
                        .help("秘密情報として検出")
                }
                Spacer()
            }

            if let displayTitle = item.displayTitle {
                Text(displayTitle)
                    .font(.system(size: cardHeight >= 140 ? 12 : 10.5, weight: .semibold))
                    .foregroundColor(ForkclipTheme.ink(0.94))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if item.isSecret {
                VStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: cardHeight >= 140 ? 24 : 16, weight: .semibold))
                        .foregroundColor(ForkclipTheme.ink(0.52))
                        .frame(width: cardHeight >= 140 ? 54 : 34, height: cardHeight >= 140 ? 54 : 34)
                        .background(ForkclipTheme.surfaceShade(0.28))
                        .cornerRadius(cardHeight >= 140 ? 27 : 17)
                    Text("秘密情報")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ForkclipTheme.ink(0.42))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let thumbnail {
                ZStack {
                    ForkclipTheme.surfaceShade(0.18)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, minHeight: thumbnailHeight, maxHeight: thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ForkclipTheme.surfaceInk(0.10), lineWidth: 1)
                )
                .accessibilityLabel("画像サムネイル")
            } else {
                Text(item.content)
                    .font(.system(size: cardHeight >= 140 ? 13 : 11.5, weight: .medium))
                    .foregroundColor(ForkclipTheme.ink(0.90))
                    .lineLimit(previewLineLimit)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(item.timestamp, style: .relative)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                clickActionBadge
            }
            .foregroundColor(ForkclipTheme.ink(0.44))
        }
        .padding(.horizontal, cardHeight >= 140 ? 14 : 9)
        .padding(.vertical, cardHeight >= 140 ? 12 : 6)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    ForkclipTheme.surfaceInk(isSelected ? 0.18 : 0.110),
                    ForkclipTheme.surfaceInk(isHovered ? 0.090 : 0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isHovered ? 0.26 : 0.14), radius: isHovered ? 8 : 3, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .animation(.spring(response: 0.25), value: isHovered)
        .accessibilityHint(clickAction.help)
    }

    private var contentLineLimit: Int {
        cardHeight >= 140 ? 5 : 2
    }

    private var previewLineLimit: Int {
        item.displayTitle == nil ? contentLineLimit : max(1, contentLineLimit - 1)
    }

    private var thumbnailHeight: CGFloat {
        cardHeight >= 140 ? 76 : 34
    }

    private var borderColor: Color {
        if isSelected {
            return .accentColor
        }
        return isHovered ? ForkclipTheme.surfaceInk(0.28) : ForkclipTheme.surfaceInk(0.085)
    }

    private func metadataBadge(title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 7.5, weight: .bold))
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.15))
        .cornerRadius(5)
    }

    private var clickActionBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: clickAction.systemImage)
                .font(.system(size: 7.5, weight: .bold))
            Text(clickAction.title)
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(ForkclipTheme.ink(0.64))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(ForkclipTheme.surfaceInk(0.075))
        .cornerRadius(5)
    }
}

struct ClipboardCardClickAction: Equatable {
    let title: String
    let systemImage: String
    let help: String
}

struct StatusBanner: View {
    let systemImage: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(ForkclipTheme.ink())
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(color.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(color.opacity(0.20))
                .frame(height: 1)
        }
    }
}

private struct LockedHistoryBanner: View {
    let status: LockedHistoryStatus
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ForkclipTheme.ink())
                    .lineLimit(1)
                Text(status.message)
                    .font(.caption2)
                    .foregroundColor(ForkclipTheme.ink(0.76))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(status.actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("診断パネルで状態と復旧手順を確認")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(color.opacity(0.16))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(color.opacity(0.20))
                .frame(height: 1)
        }
    }

    private var color: Color {
        switch status.kind {
        case .locked, .recoverable:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var systemImage: String {
        switch status.kind {
        case .locked:
            return "lock.fill"
        case .recoverable:
            return "exclamationmark.lock.fill"
        case .unavailable:
            return "xmark.octagon.fill"
        }
    }
}

struct FolderNameSheet: View {
    let title: String
    let initialName: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(title: String, initialName: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.initialName = initialName
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            TextField("フォルダ名", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    onSave(name)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct DisplayTitleSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var displayTitle: String

    init(initialTitle: String, onSave: @escaping (String) -> Void) {
        self.onSave = onSave
        _displayTitle = State(initialValue: initialTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("表示名を編集")
                .font(.headline)
            TextField("表示名", text: $displayTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }
                Button("保存") {
                    onSave(displayTitle)
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct AboutView: View {
    private var docsURL: URL? {
        DocumentationLocator.userDocsDirectory()
    }

    var body: some View {
        VStack(spacing: 18) {
            ForkclipAppIconView(size: 58)

            VStack(spacing: 4) {
                Text(AppInfo.displayName)
                    .font(.title.bold())
                Text(AppInfo.versionDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(AppInfo.shortDescription)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)

            HStack(spacing: 10) {
                Button("ユーザー Docs") {
                    if let docsURL {
                        NSWorkspace.shared.activateFileViewerSelecting([docsURL])
                    }
                }
                .disabled(docsURL == nil)

                Button("保存先を表示") {
                    if let url = try? AppPaths.applicationSupportDirectory() {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        }
        .padding(28)
        .frame(width: 420, height: 280)
    }
}
