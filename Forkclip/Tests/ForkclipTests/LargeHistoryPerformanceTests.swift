import AppKit
import XCTest
@testable import Forkclip

final class LargeHistoryPerformanceTests: XCTestCase {
    private let fixtureSize = 10_000
    private let persistedFixtureSize = 1_000
    private let persistedBenchmarkIterations = 5
    private let persistedPayloadsPerItem = 2

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

    func testPersistentLargeHistoryReloadBenchmark() async throws {
        let fixture = try await makePersistentHistoryFixture(count: persistedFixtureSize)
        defer { fixture.cleanup() }

        var durations: [TimeInterval] = []
        for _ in 0..<persistedBenchmarkIterations {
            let manager = fixture.makeReloadManager()
            let startedAt = Date()
            let snapshot = await reloadPersistedHistory(from: manager)
            durations.append(Date().timeIntervalSince(startedAt))

            let newestItem = try XCTUnwrap(snapshot.items.first)
            XCTAssertEqual(snapshot.items.count, persistedFixtureSize)
            XCTAssertEqual(snapshot.payloadCount, persistedFixtureSize * persistedPayloadsPerItem)
            XCTAssertEqual(newestItem.content, content(
                for: persistedFixtureSize - 1,
                contentType: contentType(for: persistedFixtureSize - 1)
            ))
            XCTAssertEqual(snapshot.payloadsByItemID[newestItem.id]?.count, persistedPayloadsPerItem)
        }

        let average = durations.reduce(0, +) / Double(durations.count)
        let minimum = durations.min() ?? 0
        let maximum = durations.max() ?? 0
        print(String(
            format: "Persistent large-history reload: %.3f seconds average (min %.3f, max %.3f, %d iterations, %d items, %d payloads).",
            average,
            minimum,
            maximum,
            persistedBenchmarkIterations,
            persistedFixtureSize,
            persistedFixtureSize * persistedPayloadsPerItem
        ))
    }

    private func makeLargeHistoryFixture(count: Int) -> [ClipboardItem] {
        (0..<count).map { index in
            let contentType = contentType(for: index)
            return ClipboardItem(
                id: deterministicUUID(namespace: 1, index: index),
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

    private func makePersistentHistoryFixture(count: Int) async throws -> PersistentHistoryFixture {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let databaseURL = tempDirectory.appendingPathComponent("forkclip-persistent-history.sqlite")
        let security = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
        let retentionPolicy = ClipboardRetentionPolicy(fetchLimit: count)

        let manager = DatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: retentionPolicy,
            security: security
        )
        do {
            try await seedPersistentHistory(count: count, into: manager)
        } catch {
            try? FileManager.default.removeItem(at: tempDirectory)
            throw error
        }

        return PersistentHistoryFixture(
            tempDirectory: tempDirectory,
            databaseURL: databaseURL,
            security: security,
            retentionPolicy: retentionPolicy
        )
    }

    private func seedPersistentHistory(count: Int, into manager: DatabaseManager) async throws {
        for index in 0..<count {
            let contentType = contentType(for: index)
            let item = ClipboardItem(
                id: deterministicUUID(namespace: 4, index: index),
                content: content(for: index, contentType: contentType),
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                displayTitle: "Fixture \(index)",
                bundleID: "com.example.persisted\(index % 24)",
                isSecret: index % 17 == 0,
                isFavorite: index % 11 == 0,
                usageCount: index % 9,
                lastUsedAt: index % 9 == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(20_000 + index)),
                captureCount: 1 + index % 4,
                primaryContentType: contentType
            )
            try await manager.saveItem(
                item,
                payloads: payloads(for: index, contentType: contentType),
                originBundleID: item.bundleID,
                secret: item.isSecret,
                migrated: false
            )
        }
    }

    private func reloadPersistedHistory(from manager: DatabaseManager) async -> PersistentHistorySnapshot {
        let items = await manager.fetchAll()
        var payloadsByItemID: [UUID: [ClipboardPayload]] = [:]
        for item in items {
            payloadsByItemID[item.id] = await manager.payloads(for: item.id)
        }
        return PersistentHistorySnapshot(items: items, payloadsByItemID: payloadsByItemID)
    }

    private func payloads(for index: Int, contentType: ClipboardContentType) -> [ClipboardPayload] {
        let primary = ClipboardPayload(
            id: deterministicUUID(namespace: 5, index: index),
            contentType: contentType,
            pasteboardType: pasteboardType(for: contentType),
            data: payloadData(for: index, contentType: contentType),
            preview: nil,
            rank: 0
        )
        let secondaryContentType: ClipboardContentType = contentType == .plainText ? .html : .plainText
        let secondary = ClipboardPayload(
            id: deterministicUUID(namespace: 6, index: index),
            contentType: secondaryContentType,
            pasteboardType: pasteboardType(for: secondaryContentType),
            data: payloadData(for: index, contentType: secondaryContentType),
            preview: nil,
            rank: 1
        )
        return [primary, secondary]
    }

    private func payloadData(for index: Int, contentType: ClipboardContentType) -> Data {
        switch contentType {
        case .urlText:
            return Data("https://example.com/docs/\(index)?payload=\(repeatedASCII(label: "url", index: index, minimumByteCount: 384))".utf8)
        case .image:
            return Data(repeatedASCII(label: "png-bytes", index: index, minimumByteCount: 4_096).utf8)
        case .fileURL:
            return Data("file:///Users/example/Documents/report-\(index).pdf".utf8)
        case .rtf:
            return Data("{\\rtf1\\ansi \(repeatedASCII(label: "rtf", index: index, minimumByteCount: 1_024))}".utf8)
        case .html:
            return Data("<article>\(repeatedASCII(label: "html", index: index, minimumByteCount: 1_024))</article>".utf8)
        case .plainText:
            return Data(repeatedASCII(label: "plain", index: index, minimumByteCount: 1_024).utf8)
        case .unknown:
            return Data(repeatedASCII(label: "unknown", index: index, minimumByteCount: 256).utf8)
        }
    }

    private func pasteboardType(for contentType: ClipboardContentType) -> NSPasteboard.PasteboardType {
        switch contentType {
        case .urlText:
            return .URL
        case .image:
            return .png
        case .fileURL:
            return .fileURL
        case .rtf:
            return .rtf
        case .html:
            return NSPasteboard.PasteboardType(rawValue: "public.html")
        case .plainText:
            return .string
        case .unknown:
            return NSPasteboard.PasteboardType(rawValue: "com.example.unknown")
        }
    }

    private func repeatedASCII(label: String, index: Int, minimumByteCount: Int) -> String {
        let unit = "\(label)-\(index)-"
        let repetitions = max(1, minimumByteCount / unit.utf8.count + 1)
        return String(repeating: unit, count: repetitions)
    }

    private func deterministicUUID(namespace: Int, index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", namespace * 1_000_000 + index))!
    }
}

private struct PersistentHistoryFixture {
    let tempDirectory: URL
    let databaseURL: URL
    let security: SecurityManager
    let retentionPolicy: ClipboardRetentionPolicy

    func makeReloadManager() -> DatabaseManager {
        DatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: retentionPolicy,
            security: security
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

private struct PersistentHistorySnapshot {
    let items: [ClipboardItem]
    let payloadsByItemID: [UUID: [ClipboardPayload]]

    var payloadCount: Int {
        payloadsByItemID.values.reduce(0) { $0 + $1.count }
    }
}

private extension DashboardContentScope {
    var index: Int {
        DashboardContentScope.allCases.firstIndex(of: self) ?? 0
    }
}
