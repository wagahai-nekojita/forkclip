import SwiftUI

struct DashboardToolbar: View {
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
