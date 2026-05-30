import XCTest
@testable import Forkclip

@MainActor
final class FocusedStatePerformanceTests: XCTestCase {
    func testSelectionStateTogglePerformance() {
        let items = makeItems(count: 1_000)

        measure(metrics: [XCTClockMetric()]) {
            let state = ClipboardSelectionState()
            for item in items {
                state.toggleSelection(for: item)
            }
            for item in items {
                state.toggleSelection(for: item)
            }
            XCTAssertTrue(state.selectedItemIDs.isEmpty)
        }
    }

    func testFolderStateLookupPerformance() {
        let folders = (0..<120).map { index in
            ClipboardFolder(
                id: UUID(),
                name: "Folder \(index)",
                color: "#4A90E2",
                sortOrder: index,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let selections = folders.map { HistoryFolderSelection.folder($0.id) }

        measure(metrics: [XCTClockMetric()]) {
            let state = ClipboardFolderState()
            state.folders = folders
            for selection in selections {
                _ = state.folderName(for: selection)
            }
            XCTAssertEqual(state.folderName(for: .all), "すべて")
        }
    }

    func testDiagnosticsStateUpdatePerformance() {
        let snapshots = (0..<1_000).map { index in
            DiagnosticsSnapshot(
                databasePath: "/tmp/forkclip-\(index).sqlite",
                databaseStatus: .available,
                fetchFailureCount: index % 3,
                keyState: .available,
                securityErrorDescription: nil,
                lastRecoveryBackupPath: nil,
                monitorState: .monitoring,
                lastObservedChangeCount: index,
                lastProcessedChangeAt: Date(timeIntervalSince1970: TimeInterval(index)),
                lastSaveStatus: .saveSucceeded,
                lastSaveError: nil
            )
        }

        measure(metrics: [XCTClockMetric()]) {
            let state = ClipboardDiagnosticsState()
            for snapshot in snapshots {
                state.diagnostics = snapshot
                state.bannerStatus = snapshot.fetchFailureCount > 0
                    ? .fetchFailures(count: snapshot.fetchFailureCount, detail: nil)
                    : nil
            }
            XCTAssertEqual(state.diagnostics.lastObservedChangeCount, 999)
        }
    }

    private func makeItems(count: Int) -> [ClipboardItem] {
        (0..<count).map { index in
            ClipboardItem(
                id: UUID(),
                content: "item \(index)",
                timestamp: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
    }
}
