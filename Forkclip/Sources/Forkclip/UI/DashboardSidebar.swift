import SwiftUI

struct DashboardSidebar: View {
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
