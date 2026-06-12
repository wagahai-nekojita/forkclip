import Foundation

enum DiagnosticsPanelStrings {
    static var title: String {
        localized("diagnostics.panel.title", defaultValue: "診断パネル")
    }

    static var databasePathLabel: String {
        localized("diagnostics.panel.databasePath.label", defaultValue: "データベースパス")
    }

    static var databaseStatusLabel: String {
        localized("diagnostics.panel.databaseStatus.label", defaultValue: "データベース状態")
    }

    static var keychainStatusLabel: String {
        localized("diagnostics.panel.keychainStatus.label", defaultValue: "Keychain 状態")
    }

    static var monitorStatusLabel: String {
        localized("diagnostics.panel.monitorStatus.label", defaultValue: "監視状態")
    }

    static var lastChangeCountLabel: String {
        localized("diagnostics.panel.lastChangeCount.label", defaultValue: "最終変更番号")
    }

    static var lastProcessedAtLabel: String {
        localized("diagnostics.panel.lastProcessedAt.label", defaultValue: "最終処理時刻")
    }

    static var saveResultLabel: String {
        localized("diagnostics.panel.saveResult.label", defaultValue: "保存結果")
    }

    static var saveErrorDetailLabel: String {
        localized("diagnostics.panel.saveErrorDetail.label", defaultValue: "保存エラー詳細")
    }

    static var fetchFailureCountLabel: String {
        localized("diagnostics.panel.fetchFailureCount.label", defaultValue: "復号できない履歴")
    }

    static var latestSecurityErrorLabel: String {
        localized("diagnostics.panel.latestSecurityError.label", defaultValue: "最新セキュリティエラー")
    }

    static var recoveryBackupLabel: String {
        localized("diagnostics.panel.recoveryBackup.label", defaultValue: "復旧用バックアップ")
    }

    static var noneValue: String {
        localized("diagnostics.panel.none.value", defaultValue: "なし")
    }

    static var notCreatedValue: String {
        localized("diagnostics.panel.notCreated.value", defaultValue: "未作成")
    }

    static var backupAndResetButton: String {
        localized("diagnostics.panel.backupAndReset.button", defaultValue: "バックアップして初期化")
    }

    static var backupAndResetDescription: String {
        localized("diagnostics.panel.backupAndReset.description", defaultValue: "既存 DB をバックアップし、新しい暗号鍵で履歴 DB を初期化します。")
    }

    static func fetchFailureCount(_ count: Int) -> String {
        String(format: fetchFailureCountFormat, count)
    }

    private static var fetchFailureCountFormat: String {
        localized("diagnostics.panel.fetchFailureCount.format", defaultValue: "%d 件")
    }

    private static func localized(_ key: StaticString, defaultValue: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: defaultValue, bundle: .module)
    }
}
