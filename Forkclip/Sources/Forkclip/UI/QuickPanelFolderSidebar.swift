import SwiftUI

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
