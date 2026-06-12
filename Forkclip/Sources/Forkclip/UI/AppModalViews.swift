import SwiftUI
import AppKit

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
