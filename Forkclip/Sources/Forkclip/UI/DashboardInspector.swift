import SwiftUI

struct DashboardInspector: View {
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
