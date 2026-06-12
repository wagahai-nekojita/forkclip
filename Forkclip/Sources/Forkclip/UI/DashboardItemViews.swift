import SwiftUI

struct DashboardHighlightStrip: View {
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

struct DashboardItemList: View {
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

struct DashboardEmptyPane: View {
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
