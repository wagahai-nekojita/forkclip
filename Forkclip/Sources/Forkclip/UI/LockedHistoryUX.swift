import Foundation

struct LockedHistoryStatus: Equatable {
    enum Kind: Equatable {
        case locked
        case recoverable
        case unavailable
    }

    let kind: Kind
    let title: String
    let message: String
    let actionTitle: String
}

enum LockedHistoryUX {
    static func status(for diagnostics: DiagnosticsSnapshot) -> LockedHistoryStatus? {
        if diagnostics.keyState == .missing {
            return LockedHistoryStatus(
                kind: .locked,
                title: "履歴はロックされています",
                message: "暗号鍵を確認できないため履歴を表示できません。診断パネルでバックアップ復旧を確認してください。",
                actionTitle: "診断を開く"
            )
        }

        if diagnostics.keyState == .failed || diagnostics.databaseStatus == .failed {
            return LockedHistoryStatus(
                kind: .unavailable,
                title: "履歴を利用できません",
                message: "Keychain または DB の状態に問題があります。診断パネルで詳細を確認してください。",
                actionTitle: "診断を開く"
            )
        }

        if diagnostics.fetchFailureCount > 0 {
            return LockedHistoryStatus(
                kind: .recoverable,
                title: "復号できない履歴があります",
                message: "\(diagnostics.fetchFailureCount) 件の履歴を復号できません。診断パネルで状態とバックアップ復旧を確認してください。",
                actionTitle: "診断を開く"
            )
        }

        return nil
    }
}
