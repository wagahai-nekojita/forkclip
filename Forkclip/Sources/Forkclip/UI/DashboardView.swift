import SwiftUI
import AppKit

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

private struct DashboardSidebar: View {
    let manager: ClipboardManager
    @ObservedObject var historyState: ClipboardHistoryState
    @ObservedObject var folderState: ClipboardFolderState
    @Binding var contentScope: DashboardContentScope

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                DashboardAppIcon()

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.displayName)
                        .font(.title3.bold())
                        .foregroundColor(ForkclipTheme.ink())
                    Text("Dashboard")
                        .font(.caption)
                        .foregroundColor(ForkclipTheme.ink(0.58))
                }
            }
            .padding(.bottom, 4)

            DashboardSidebarSection(title: "履歴") {
                DashboardSidebarButton(
                    title: "すべての履歴",
                    systemImage: "tray.full",
                    count: historyState.items.count,
                    isSelected: folderState.selectedFolder == .all && historyState.sourceAppFilter.isEmpty && !historyState.isFavoritesOnly && contentScope == .all
                ) {
                    folderState.selectedFolder = .all
                    historyState.sourceAppFilter = ""
                    historyState.isFavoritesOnly = false
                    contentScope = .all
                }

                DashboardSidebarButton(
                    title: "お気に入り",
                    systemImage: "star.fill",
                    count: historyState.items.filter(\.isFavorite).count,
                    isSelected: historyState.isFavoritesOnly
                ) {
                    historyState.isFavoritesOnly = true
                }

                DashboardSidebarButton(
                    title: "未整理",
                    systemImage: "tray",
                    count: historyState.items.filter { folderState.folderIDs(for: $0).isEmpty }.count,
                    isSelected: folderState.selectedFolder == .unfiled
                ) {
                    folderState.selectedFolder = .unfiled
                }
            }

            DashboardSidebarSection(title: "種類") {
                ForEach(DashboardContentScope.allCases) { scope in
                    DashboardSidebarButton(
                        title: scope.title,
                        systemImage: scope.systemImage,
                        count: scope.filteredItems(from: historyState.items).count,
                        isSelected: contentScope == scope
                    ) {
                        contentScope = scope
                    }
                }
            }

            DashboardSidebarSection(title: "フォルダ") {
                ForEach(folderState.folders) { folder in
                    DashboardSidebarButton(
                        title: folder.name,
                        systemImage: "folder",
                        count: historyState.items.filter { folderState.folderIDs(for: $0).contains(folder.id) }.count,
                        isSelected: folderState.selectedFolder == .folder(folder.id)
                    ) {
                        folderState.selectedFolder = .folder(folder.id)
                    }
                }
            }

            DashboardSidebarSection(title: "ソース") {
                ForEach(manager.sourceBundleIDs, id: \.self) { bundleID in
                    DashboardSidebarButton(
                        title: manager.sourceAppDisplayName(for: bundleID),
                        systemImage: "app.dashed",
                        count: historyState.items.filter { $0.bundleID == bundleID }.count,
                        isSelected: historyState.sourceAppFilter == bundleID
                    ) {
                        historyState.sourceAppFilter = bundleID
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 238)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ForkclipTheme.surfaceShade(0.22))
    }
}

private struct DashboardAppIcon: View {
    private let size: CGFloat = 46

    var body: some View {
        ForkclipAppIconView(size: size)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DashboardSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(ForkclipTheme.ink(0.45))
                .textCase(.uppercase)
                .padding(.horizontal, 8)
            content
        }
    }
}

private struct DashboardSidebarButton: View {
    let title: String
    let systemImage: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 17)
                    .foregroundColor(isSelected ? .white : .accentColor)

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : ForkclipTheme.ink(0.76))

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : ForkclipTheme.ink(0.56))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(ForkclipTheme.surfaceInk(isSelected ? 0.18 : 0.08))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor.opacity(0.46) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardToolbar: View {
    let manager: ClipboardManager
    @ObservedObject var historyState: ClipboardHistoryState
    let itemCount: Int
    let openSettings: () -> Void
    let openAbout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("履歴を検索", text: $historyState.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260, idealWidth: 360, maxWidth: 440)

            DashboardStatusPill(
                title: "Queue",
                value: historyState.queue.isEmpty ? "0" : "\(historyState.queue.count)",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                isActive: !historyState.queue.isEmpty
            )

            DashboardStatusPill(
                title: "Private",
                value: historyState.isPrivateMode ? "ON" : "OFF",
                systemImage: "eye.slash",
                isActive: historyState.isPrivateMode
            )

            Spacer()

            Text("\(itemCount) 件")
                .font(.caption.weight(.semibold))
                .foregroundColor(ForkclipTheme.ink(0.62))

            ToolbarIconButton(systemImage: "info.circle", help: "\(AppInfo.displayName) について", action: openAbout)
            ToolbarIconButton(systemImage: "gearshape", help: "設定", action: openSettings)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(ForkclipTheme.surfaceShade(0.18))
    }
}

private struct DashboardStatusPill: View {
    let title: String
    let value: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .accentColor : ForkclipTheme.ink(0.62))

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ForkclipTheme.ink(0.82))

            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isActive ? .white : ForkclipTheme.ink(0.52))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isActive ? Color.accentColor.opacity(0.42) : ForkclipTheme.surfaceInk(0.08))
                .cornerRadius(7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(ForkclipTheme.surfaceInk(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(ForkclipTheme.surfaceInk(0.08), lineWidth: 1)
        )
        .cornerRadius(9)
    }
}

private struct DashboardHighlightStrip: View {
    @ObservedObject var manager: ClipboardManager
    let items: [ClipboardItem]
    let selectedID: UUID?
    let selectItem: (ClipboardItem) -> Void
    let copyItem: (ClipboardItem) -> Void
    let editDisplayTitle: (ClipboardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("よく使うもの")
                    .font(.headline)
                    .foregroundColor(ForkclipTheme.ink())
                Text("ダブルクリックでコピー")
                    .font(.caption)
                    .foregroundColor(ForkclipTheme.ink(0.48))
                Spacer()
            }

            if items.isEmpty {
                DashboardEmptyPane(title: "まだ使用回数がありません", systemImage: "clock.arrow.circlepath")
                    .frame(height: 128)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            DashboardHighlightCard(
                                manager: manager,
                                item: item,
                                isSelected: selectedID == item.id
                            )
                            .frame(width: 214, height: 132)
                            .onTapGesture {
                                selectItem(item)
                            }
                            .onTapGesture(count: 2) {
                                copyItem(item)
                            }
                            .contextMenu {
                                Button("表示名を編集…") {
                                    editDisplayTitle(item)
                                }
                                Button("コピー") {
                                    copyItem(item)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(18)
        .frame(height: 204, alignment: .top)
        .background(ForkclipTheme.surfaceInk(0.025))
    }
}

private struct DashboardHighlightCard: View {
    @ObservedObject var manager: ClipboardManager
    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(DashboardContentScope.inferredScope(for: item).title, systemImage: DashboardContentScope.inferredScope(for: item).systemImage)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                Text(DashboardFormatters.usageSummary(for: item))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(ForkclipTheme.ink(0.58))
                Spacer()
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                }
            }

            if let displayTitle = item.displayTitle {
                Text(displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(ForkclipTheme.ink(0.94))
                    .lineLimit(1)
            }

            if let thumbnail = manager.imageThumbnail(for: item) {
                ZStack {
                    ForkclipTheme.surfaceShade(0.18)
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ForkclipTheme.surfaceInk(0.10), lineWidth: 1)
                )
                .accessibilityLabel("画像サムネイル")
            } else {
                Text(DashboardFormatters.previewText(for: item))
                    .font(.system(size: 12.5))
                    .lineLimit(4)
                    .foregroundColor(ForkclipTheme.ink(item.isSecret ? 0.45 : 0.9))
            }

            Spacer()

            HStack(spacing: 6) {
                Text(DashboardFormatters.typeSummary(for: item))
                Spacer()
                Text(DashboardFormatters.lastUsedSummary(for: item))
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(ForkclipTheme.ink(0.48))
            .lineLimit(1)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    ForkclipTheme.surfaceInk(isSelected ? 0.16 : 0.10),
                    ForkclipTheme.surfaceInk(isSelected ? 0.10 : 0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.95) : ForkclipTheme.surfaceInk(0.10), lineWidth: isSelected ? 2 : 1)
        )
        .cornerRadius(8)
    }
}

private struct DashboardItemList: View {
    @ObservedObject var manager: ClipboardManager
    let items: [ClipboardItem]
    let selectedID: UUID?
    let selectItem: (ClipboardItem) -> Void
    let copyItem: (ClipboardItem) -> Void
    let editDisplayTitle: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            DashboardListHeader()

            if items.isEmpty {
                DashboardEmptyPane(title: "一致する履歴がありません", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            DashboardItemRow(
                                manager: manager,
                                item: item,
                                isSelected: selectedID == item.id,
                                selectItem: selectItem,
                                copyItem: copyItem,
                                editDisplayTitle: editDisplayTitle
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct DashboardListHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("時刻")
                .frame(width: 64, alignment: .leading)
            Text("内容")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("分類")
                .frame(width: 96, alignment: .leading)
            Text("コピー")
                .frame(width: 58, alignment: .leading)
            Text("ソース")
                .frame(width: 104, alignment: .leading)
            Text("")
                .frame(width: 66)
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(ForkclipTheme.ink(0.42))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ForkclipTheme.surfaceShade(0.16))
    }
}

private struct DashboardItemRow: View {
    @ObservedObject var manager: ClipboardManager
    let item: ClipboardItem
    let isSelected: Bool
    let selectItem: (ClipboardItem) -> Void
    let copyItem: (ClipboardItem) -> Void
    let editDisplayTitle: (ClipboardItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(DashboardFormatters.time.string(from: item.lastCapturedAt))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ForkclipTheme.ink(0.56))
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 9) {
                Image(systemName: DashboardContentScope.inferredScope(for: item).systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor.opacity(0.18))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 2) {
                    if let displayTitle = item.displayTitle {
                        Text(displayTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(ForkclipTheme.ink(0.94))
                            .lineLimit(1)
                    }
                    Text(DashboardFormatters.previewText(for: item))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(ForkclipTheme.ink(item.isSecret ? 0.45 : 0.92))
                        .lineLimit(1)
                    Text(DashboardFormatters.folderSummary(for: item, manager: manager))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(ForkclipTheme.ink(0.43))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.yellow)
                }
                Text(DashboardFormatters.typeSummary(for: item))
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(ForkclipTheme.ink(0.58))
            .frame(width: 96, alignment: .leading)

            Text(DashboardFormatters.captureSummary(for: item))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(item.captureCount > 1 ? .accentColor : ForkclipTheme.ink(0.42))
                .lineLimit(1)
                .frame(width: 58, alignment: .leading)

            Text(item.bundleID.map(manager.sourceAppDisplayName(for:)) ?? "このMac")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(ForkclipTheme.ink(0.58))
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)

            HStack(spacing: 4) {
                Button {
                    copyItem(item)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(ForkclipTheme.ink(0.74))
                .help("コピー")

                Button {
                    editDisplayTitle(item)
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(ForkclipTheme.ink(0.74))
                .help("表示名を編集")
            }
            .frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.22) : ForkclipTheme.surfaceInk(0.02))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ForkclipTheme.surfaceInk(0.06))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectItem(item)
        }
        .onTapGesture(count: 2) {
            copyItem(item)
        }
        .contextMenu {
            Button("表示名を編集…") {
                editDisplayTitle(item)
            }
            Button("コピー") {
                copyItem(item)
            }
        }
    }
}

private struct DashboardInspector: View {
    @ObservedObject var manager: ClipboardManager
    let item: ClipboardItem?
    let copyItem: (ClipboardItem) -> Void
    let editDisplayTitle: (ClipboardItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let item {
                HStack(alignment: .top) {
                    Label(DashboardContentScope.inferredScope(for: item).title, systemImage: DashboardContentScope.inferredScope(for: item).systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                    Spacer()
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }
                }

                if let displayTitle = item.displayTitle {
                    Text(displayTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(ForkclipTheme.ink(0.94))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(DashboardFormatters.previewText(for: item))
                    .font(.system(size: 13.5))
                    .foregroundColor(ForkclipTheme.ink(item.isSecret ? 0.45 : 0.92))
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(ForkclipTheme.surfaceShade(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ForkclipTheme.surfaceInk(0.08), lineWidth: 1)
                    )
                    .cornerRadius(8)

                HStack(spacing: 8) {
                    Button {
                        copyItem(item)
                    } label: {
                        Label("コピー", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        editDisplayTitle(item)
                    } label: {
                        Label("表示名", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("情報")
                        .font(.caption.bold())
                        .foregroundColor(ForkclipTheme.ink(0.68))

                    DashboardMetadataRow(label: "種類", value: DashboardFormatters.typeSummary(for: item))
                    DashboardMetadataRow(label: "文字数", value: "\(item.content.count)")
                    DashboardMetadataRow(label: "コピー回数", value: DashboardFormatters.captureSummary(for: item))
                    DashboardMetadataRow(label: "最終コピー", value: DashboardFormatters.fullDate.string(from: item.lastCapturedAt))
                    DashboardMetadataRow(label: "使用回数", value: DashboardFormatters.usageSummary(for: item))
                    DashboardMetadataRow(label: "最終使用", value: item.lastUsedAt.map { DashboardFormatters.fullDate.string(from: $0) } ?? "-")
                    DashboardMetadataRow(label: "作成日時", value: DashboardFormatters.fullDate.string(from: item.timestamp))
                    DashboardMetadataRow(label: "フォルダ", value: DashboardFormatters.folderSummary(for: item, manager: manager))
                    DashboardMetadataRow(label: "ソース", value: item.bundleID.map(manager.sourceAppDisplayName(for:)) ?? "このMac")
                    DashboardMetadataRow(label: "Bundle ID", value: item.bundleID ?? "-")
                }

                Spacer()
            } else {
                DashboardEmptyPane(title: "項目を選択", systemImage: "sidebar.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ForkclipTheme.surfaceShade(0.20))
    }
}

private struct DashboardMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(ForkclipTheme.ink(0.42))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(ForkclipTheme.ink(0.82))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct DashboardEmptyPane: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(ForkclipTheme.ink(0.34))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ForkclipTheme.ink(0.56))
        }
    }
}

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
