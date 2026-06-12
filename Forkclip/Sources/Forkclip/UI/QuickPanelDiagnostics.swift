import SwiftUI

struct DiagnosticsPanel: View {
    let manager: ClipboardManager
    @ObservedObject var diagnosticsState: ClipboardDiagnosticsState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(DiagnosticsPanelStrings.title)
                    .font(.caption.bold())
                    .foregroundColor(ForkclipTheme.ink())
                Spacer()
                Text("\(AppInfo.displayName) \(AppInfo.versionDisplay)")
                    .font(.caption2)
                    .foregroundColor(ForkclipTheme.ink(0.55))
            }

            DiagnosticRow(label: DiagnosticsPanelStrings.databasePathLabel, value: ClipboardStatusFormatter.databasePathText(diagnosticsState.diagnostics.databasePath))
            DiagnosticRow(label: DiagnosticsPanelStrings.databaseStatusLabel, value: ClipboardStatusFormatter.databaseText(diagnosticsState.diagnostics.databaseStatus))
            DiagnosticRow(label: DiagnosticsPanelStrings.keychainStatusLabel, value: ClipboardStatusFormatter.keyText(diagnosticsState.diagnostics.keyState))
            DiagnosticRow(label: DiagnosticsPanelStrings.monitorStatusLabel, value: ClipboardStatusFormatter.monitorText(diagnosticsState.diagnostics.monitorState))
            DiagnosticRow(label: DiagnosticsPanelStrings.lastChangeCountLabel, value: ClipboardStatusFormatter.changeCountText(diagnosticsState.diagnostics.lastObservedChangeCount))
            DiagnosticRow(
                label: DiagnosticsPanelStrings.lastProcessedAtLabel,
                value: ClipboardStatusFormatter.diagnosticsProcessedAtText(diagnosticsState.diagnostics.lastProcessedChangeAt)
            )
            DiagnosticRow(label: DiagnosticsPanelStrings.saveResultLabel, value: ClipboardStatusFormatter.operationText(diagnosticsState.diagnostics.lastSaveStatus))
            DiagnosticRow(label: DiagnosticsPanelStrings.saveErrorDetailLabel, value: diagnosticsState.diagnostics.lastSaveError ?? DiagnosticsPanelStrings.noneValue)
            DiagnosticRow(label: DiagnosticsPanelStrings.fetchFailureCountLabel, value: DiagnosticsPanelStrings.fetchFailureCount(diagnosticsState.diagnostics.fetchFailureCount))
            DiagnosticRow(label: DiagnosticsPanelStrings.latestSecurityErrorLabel, value: diagnosticsState.diagnostics.securityErrorDescription ?? DiagnosticsPanelStrings.noneValue)
            DiagnosticRow(label: DiagnosticsPanelStrings.recoveryBackupLabel, value: diagnosticsState.diagnostics.lastRecoveryBackupPath ?? DiagnosticsPanelStrings.notCreatedValue)

            if diagnosticsState.diagnostics.keyState == .missing || diagnosticsState.diagnostics.fetchFailureCount > 0 {
                HStack(spacing: 12) {
                    Button(DiagnosticsPanelStrings.backupAndResetButton) {
                        Task { await manager.recoverFromMissingKey() }
                    }
                    .buttonStyle(.borderedProminent)

                    Text(DiagnosticsPanelStrings.backupAndResetDescription)
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

struct LockedHistoryBanner: View {
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
