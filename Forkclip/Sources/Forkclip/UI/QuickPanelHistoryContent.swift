import SwiftUI
import AppKit

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
