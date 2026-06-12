import SwiftUI

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
