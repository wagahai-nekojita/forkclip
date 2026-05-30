import XCTest
@testable import Forkclip

final class LockedHistoryUXTests: XCTestCase {
    func testMissingKeyShowsLockedRecoveryEntryPoint() {
        let status = LockedHistoryUX.status(for: snapshot(keyState: .missing))

        XCTAssertEqual(status?.kind, .locked)
        XCTAssertEqual(status?.title, "履歴はロックされています")
        XCTAssertEqual(status?.actionTitle, "診断を開く")
        XCTAssertTrue(status?.message.contains("バックアップ復旧") == true)
    }

    func testFetchFailuresShowRecoverableState() {
        let status = LockedHistoryUX.status(for: snapshot(fetchFailureCount: 3))

        XCTAssertEqual(status?.kind, .recoverable)
        XCTAssertEqual(status?.title, "復号できない履歴があります")
        XCTAssertTrue(status?.message.contains("3 件") == true)
        XCTAssertTrue(status?.message.contains("診断パネル") == true)
    }

    func testFailedKeyOrDatabaseShowsUnavailableState() {
        let keyStatus = LockedHistoryUX.status(for: snapshot(keyState: .failed))
        let databaseStatus = LockedHistoryUX.status(for: snapshot(databaseStatus: .failed))

        XCTAssertEqual(keyStatus?.kind, .unavailable)
        XCTAssertEqual(databaseStatus?.kind, .unavailable)
        XCTAssertEqual(keyStatus?.actionTitle, "診断を開く")
    }

    func testHealthyDiagnosticsDoNotShowLockedHistoryState() {
        XCTAssertNil(LockedHistoryUX.status(for: snapshot()))
    }

    private func snapshot(
        databaseStatus: DatabaseStatus = .available,
        fetchFailureCount: Int = 0,
        keyState: SecurityKeyState = .available
    ) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            databasePath: "/tmp/forkclip.sqlite",
            databaseStatus: databaseStatus,
            fetchFailureCount: fetchFailureCount,
            keyState: keyState,
            securityErrorDescription: nil,
            lastRecoveryBackupPath: nil,
            monitorState: .monitoring,
            lastObservedChangeCount: 10,
            lastProcessedChangeAt: Date(timeIntervalSince1970: 1_721_230_967),
            lastSaveStatus: .saveSucceeded,
            lastSaveError: nil
        )
    }
}
