#if canImport(XCTest)
import XCTest
@testable import Forkclip

final class DiagnosticsPanelStringsTests: XCTestCase {
    func testStringCatalogProvidesDiagnosticsPanelEntries() {
        XCTAssertEqual(
            Bundle.module.localizedString(forKey: "diagnostics.panel.title", value: nil, table: nil),
            "診断パネル"
        )
    }

    func testDiagnosticsPanelStringsPreserveCurrentJapaneseCopy() {
        XCTAssertEqual(DiagnosticsPanelStrings.title, "診断パネル")
        XCTAssertEqual(DiagnosticsPanelStrings.databasePathLabel, "データベースパス")
        XCTAssertEqual(DiagnosticsPanelStrings.databaseStatusLabel, "データベース状態")
        XCTAssertEqual(DiagnosticsPanelStrings.keychainStatusLabel, "Keychain 状態")
        XCTAssertEqual(DiagnosticsPanelStrings.monitorStatusLabel, "監視状態")
        XCTAssertEqual(DiagnosticsPanelStrings.lastChangeCountLabel, "最終変更番号")
        XCTAssertEqual(DiagnosticsPanelStrings.lastProcessedAtLabel, "最終処理時刻")
        XCTAssertEqual(DiagnosticsPanelStrings.saveResultLabel, "保存結果")
        XCTAssertEqual(DiagnosticsPanelStrings.saveErrorDetailLabel, "保存エラー詳細")
        XCTAssertEqual(DiagnosticsPanelStrings.fetchFailureCountLabel, "復号できない履歴")
        XCTAssertEqual(DiagnosticsPanelStrings.fetchFailureCount(3), "3 件")
        XCTAssertEqual(DiagnosticsPanelStrings.latestSecurityErrorLabel, "最新セキュリティエラー")
        XCTAssertEqual(DiagnosticsPanelStrings.recoveryBackupLabel, "復旧用バックアップ")
        XCTAssertEqual(DiagnosticsPanelStrings.noneValue, "なし")
        XCTAssertEqual(DiagnosticsPanelStrings.notCreatedValue, "未作成")
        XCTAssertEqual(DiagnosticsPanelStrings.backupAndResetButton, "バックアップして初期化")
        XCTAssertEqual(DiagnosticsPanelStrings.backupAndResetDescription, "既存 DB をバックアップし、新しい暗号鍵で履歴 DB を初期化します。")
    }
}
#endif
