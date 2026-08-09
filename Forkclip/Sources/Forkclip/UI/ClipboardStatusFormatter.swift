import Foundation

enum ClipboardStatusFormatter {
    static func databasePathText(_ path: String?) -> String {
        path ?? "未確認"
    }

    static func databaseText(_ status: DatabaseStatus) -> String {
        switch status {
        case .uninitialized:
            return "未初期化"
        case .available:
            return "利用可能"
        case .failed:
            return "利用不可"
        }
    }

    static func keyText(_ state: SecurityKeyState) -> String {
        switch state {
        case .unchecked:
            return "未確認"
        case .available:
            return "利用可能"
        case .missing:
            return "見つかりません"
        case .failed:
            return "確認失敗"
        }
    }

    static func monitorText(_ state: ClipboardMonitorState) -> String {
        switch state {
        case .unchecked:
            return "未確認"
        case .stopped:
            return "停止"
        case .starting:
            return "開始中"
        case .monitoring:
            return "監視中"
        case .failed(let message):
            return "失敗: \(message)"
        }
    }

    static func operationText(_ status: ClipboardOperationStatus) -> String {
        switch status {
        case .notRun:
            return "未実行"
        case .saveSucceeded:
            return "保存成功"
        case .selfCopyIgnored:
            return "自己コピーを無視"
        case .privateModeSkipped:
            return "プライベートモードで未保存"
        case .blacklistedApplicationIgnored:
            return "除外アプリのため未保存"
        case .sourceApplicationUnknownSkipped:
            return "コピー元アプリを確認できないため未保存"
        case .clipboardChangedDuringCaptureSkipped:
            return "クリップボード変更競合のため未保存"
        case .concealedContentSkipped:
            return "機微マーカー付きのため未保存"
        case .resourceLimitSkipped:
            return "容量制限のため未保存"
        case .unsupportedContentSkipped:
            return "未対応形式のため未保存"
        case .emptyStringIgnored:
            return "空文字列を無視"
        case .duplicateIgnored:
            return "重複を無視"
        case .duplicateRecorded:
            return "重複を記録"
        case .saveFailed:
            return "保存失敗"
        case .startupSelfCheckFailed:
            return "起動時チェック失敗"
        case .recoverySucceeded:
            return "復旧完了"
        case .recoveryFailed:
            return "復旧失敗"
        }
    }

    static func bannerText(_ status: ClipboardBannerStatus) -> String {
        switch status {
        case .monitorNotRunning:
            return "クリップボード監視が開始されていません。診断パネルを確認してください。"
        case .saveFailed(let detail):
            return "クリップボードの保存に失敗しました。\(detail ?? "診断パネルを確認してください。")"
        case .keyProblem(let detail):
            return "暗号鍵を確認できません。\(detail ?? "Keychain の状態を確認してください。")"
        case .fetchFailures(let count, let detail):
            return "復号できない履歴が \(count) 件あります。\(detail ?? "暗号鍵または保存データを確認してください。")"
        case .autoPasteFailed(let target):
            return "\(target ?? "直前のアプリ") へ貼り付けできませんでした。内容はクリップボードにコピー済みです。"
        case .waitingForData:
            return "新規データの取り込み待ちです。"
        }
    }

    static func recoveryText(_ status: ClipboardRecoveryStatus) -> String {
        switch status {
        case .succeeded:
            return "既存 DB をバックアップし、新しい暗号鍵で初期化しました。"
        case .failed:
            return "復旧に失敗しました。Keychain とバックアップ権限を確認してください。"
        }
    }

    static func folderText(_ status: ClipboardFolderStatus) -> String {
        switch status {
        case .emptyName:
            return "フォルダ名を入力してください。"
        case .updateFailed:
            return "フォルダ名を更新できませんでした。"
        case .assignFailed:
            return "フォルダへ移動できませんでした。"
        case .favoriteUpdateFailed:
            return "お気に入りを更新できませんでした。"
        case .displayTitleUpdateFailed:
            return "表示名を更新できませんでした。"
        }
    }

    static func changeCountText(_ changeCount: Int?) -> String {
        changeCount.map(String.init) ?? "未確認"
    }

    static func diagnosticsProcessedAtText(_ date: Date?) -> String {
        guard let date else {
            return "未処理"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
