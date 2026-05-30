import XCTest
@testable import Forkclip

final class LargeHistoryPerformanceTests: XCTestCase {
    private let fixtureSize = 10_000

    func testDashboardScopeFilteringPerformance() {
        let items = makeLargeHistoryFixture(count: fixtureSize)

        measure(metrics: [XCTClockMetric()]) {
            let counts = DashboardContentScope.allCases.map { scope in
                scope.filteredItems(from: items).count
            }

            XCTAssertEqual(counts.count, DashboardContentScope.allCases.count)
            XCTAssertEqual(counts[DashboardContentScope.all.index], items.count)
        }
    }

    func testDashboardFrequentItemsOrderingPerformance() {
        let items = makeLargeHistoryFixture(count: fixtureSize)

        measure(metrics: [XCTClockMetric()]) {
            let orderedItems = DashboardFrequentItems.orderedItems(from: items, limit: 10)

            XCTAssertEqual(orderedItems.count, 10)
            XCTAssertTrue(orderedItems.allSatisfy { $0.usageCount > 0 })
        }
    }

    private func makeLargeHistoryFixture(count: Int) -> [ClipboardItem] {
        (0..<count).map { index in
            let contentType = contentType(for: index)
            return ClipboardItem(
                id: UUID(),
                content: content(for: index, contentType: contentType),
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                bundleID: "com.example.source\(index % 24)",
                isSecret: index % 17 == 0,
                isFavorite: index % 11 == 0,
                usageCount: index % 9,
                lastUsedAt: index % 9 == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(20_000 + index)),
                primaryContentType: contentType
            )
        }
    }

    private func contentType(for index: Int) -> ClipboardContentType {
        switch index % 8 {
        case 0:
            return .urlText
        case 1:
            return .image
        case 2:
            return .fileURL
        case 3:
            return .rtf
        case 4:
            return .html
        default:
            return .plainText
        }
    }

    private func content(for index: Int, contentType: ClipboardContentType) -> String {
        switch contentType {
        case .urlText:
            return "https://example.com/docs/\(index)"
        case .image:
            return "画像 \(index)"
        case .fileURL:
            return "ファイル: report-\(index).pdf"
        case .rtf:
            return "リッチテキスト \(index)"
        case .html:
            return "<p>HTML \(index)</p>"
        case .plainText where index % 13 == 0:
            return "struct Fixture\(index) { let value = \(index) }"
        case .plainText:
            return "plain clipboard text \(index)"
        case .unknown:
            return "unknown \(index)"
        }
    }
}

private extension DashboardContentScope {
    var index: Int {
        DashboardContentScope.allCases.firstIndex(of: self) ?? 0
    }
}
