#if canImport(XCTest)
import XCTest
import AppKit
import SQLite
@testable import Forkclip

@MainActor
final class ClipboardManagerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        _ = await MainActor.run { NSApplication.shared }
    }

    func testPollDoesNotSaveWithoutChangeCountUpdate() async {
        let pasteboard = FakePasteboard(changeCount: 5, stringValue: "initial")
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .notRun)
    }

    func testPollSavesExactlyOnceForSingleChange() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("captured")
        await manager.pollClipboardForTests()
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "captured")
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
        XCTAssertEqual(feedbackEvents, [.externalCaptureSaved])
    }

    func testFormattedNormalTextSavesAsNonSecretItem() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let security = FakeSecurityProvider()
        security.secretDetector = { SecurityManager.shared.isLikelySecret($0) }
        let manager = await makeManager(pasteboard: pasteboard, store: store, security: security)

        pasteboard.write("""
        # Dashboard status
        非公開の誤判定を確認する。Atlas / Codex 由来の通常テキストを保存する。
        - Private: OFF
        - Queue: 0
        - Validation: swift test --scratch-path /tmp/forkclip-validation-test-build
        """)
        await manager.pollClipboardForTests()

        let item = try XCTUnwrap(manager.items.first)
        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertFalse(item.isSecret)
        XCTAssertNotEqual(DashboardContentScope.inferredScope(for: item), .privateItems)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testCustomSecretPatternAppliesToNewCapture() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let security = SecurityManager(
            customSecretPatternsURL: tempDirectory.appendingPathComponent("custom_secret_patterns.json"),
            keyStorage: SecurityManager.InMemoryKeyStorage()
        )
        try security.saveCustomSecretPatterns([
            CustomSecretPattern(name: "Internal deploy token", pattern: #"DEPLOY-[A-Z0-9]{16}"#)
        ])

        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store, security: security)

        pasteboard.write("DEPLOY-ABCDEF1234567890")
        await manager.pollClipboardForTests()

        let item = try XCTUnwrap(manager.items.first)
        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertTrue(item.isSecret)
        XCTAssertEqual(DashboardContentScope.inferredScope(for: item), .privateItems)
    }

    func testExistingFalsePositiveSecretItemIsReclassifiedOnLoad() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(
            id: UUID(),
            content: """
            ほとんどが非公開になってしまっている。Atlas/Codex/Claude由来の履歴がマスク表示になっている。
            Example token=abc123DEF456!@#7890 appears inside prose, but this whole note is not a credential.
            """,
            timestamp: Date(),
            isSecret: true,
            primaryContentType: .plainText
        )
        store.seedItems([item])
        let security = FakeSecurityProvider()
        security.secretDetector = { SecurityManager.shared.isLikelySecret($0) }

        let manager = await makeManager(pasteboard: pasteboard, store: store, security: security)

        let loadedItem = try XCTUnwrap(manager.items.first)
        XCTAssertFalse(loadedItem.isSecret)
        XCTAssertFalse(try XCTUnwrap(store.savedItems.first).isSecret)
        XCTAssertNotEqual(DashboardContentScope.inferredScope(for: loadedItem), .privateItems)
    }

    func testExistingHighConfidenceSecretStaysSecretOnLoad() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(
            id: UUID(),
            content: "token=abc123DEF456!@#7890",
            timestamp: Date(),
            isSecret: true,
            primaryContentType: .plainText
        )
        store.seedItems([item])
        let security = FakeSecurityProvider()
        security.secretDetector = { SecurityManager.shared.isLikelySecret($0) }

        let manager = await makeManager(pasteboard: pasteboard, store: store, security: security)

        let loadedItem = try XCTUnwrap(manager.items.first)
        XCTAssertTrue(loadedItem.isSecret)
        XCTAssertTrue(try XCTUnwrap(store.savedItems.first).isSecret)
        XCTAssertEqual(DashboardContentScope.inferredScope(for: loadedItem), .privateItems)
    }

    func testTextWithAdditionalPasteboardTypesStillSavesText() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("https://example.com", types: [.string, NSPasteboard.PasteboardType(rawValue: "public.url")])
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "https://example.com")
        XCTAssertEqual(manager.items.first?.primaryContentType, .urlText)
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.contentType), [.urlText, .plainText])
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testImageOnlyPasteboardChangeSavesPayload() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        pasteboard.writeData(imageData, forType: .png)
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "画像")
        XCTAssertEqual(manager.items.first?.primaryContentType, .image)
        let payload = store.savedPayloadsForFirstItem().first
        XCTAssertEqual(payload?.contentType, .image)
        XCTAssertEqual(payload?.pasteboardType, .png)
        XCTAssertEqual(payload?.data, imageData)
        XCTAssertEqual(payload?.preview, "画像")
        XCTAssertEqual(payload?.rank, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
        XCTAssertEqual(feedbackEvents, [.externalCaptureSaved])
    }

    func testImagePasteboardChangeFallsBackToNSImageReadableData() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let fallbackTIFFData = Data([0x49, 0x49, 0x2A, 0x00])

        pasteboard.writeImageTypeWithoutDirectData(.png, fallbackData: fallbackTIFFData)
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "画像")
        XCTAssertEqual(manager.items.first?.primaryContentType, .image)
        let payload = store.savedPayloadsForFirstItem().first
        XCTAssertEqual(payload?.contentType, .image)
        XCTAssertEqual(payload?.pasteboardType, .tiff)
        XCTAssertEqual(payload?.data, fallbackTIFFData)
        XCTAssertEqual(payload?.rank, 0)
    }

    func testMixedFileURLAndImagePasteboardChangePrefersImagePrimaryType() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let fileURL = "file:///Users/example/Desktop/cleanshot.png"

        pasteboard.writeDataByType(
            [.png: imageData],
            stringsByType: [.fileURL: fileURL],
            types: [.fileURL, .png]
        )
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "画像")
        XCTAssertEqual(manager.items.first?.primaryContentType, .image)
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.contentType), [.image, .fileURL])
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.pasteboardType), [.png, .fileURL])
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.rank), [0, 1])
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.data), [imageData, Data(fileURL.utf8)])
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testRealSQLitePersistenceCapturesPlainTextWithoutPlaintextRows() async throws {
        let fixture = try makeRealPersistenceFixture()
        defer { fixture.cleanup() }
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let manager = await fixture.makeManager(pasteboard: pasteboard)
        let plainText = "real sqlite plain text"

        pasteboard.write(plainText)
        await manager.pollClipboardForTests()

        let captured = try XCTUnwrap(manager.items.first)
        XCTAssertEqual(captured.content, plainText)
        XCTAssertFalse(captured.isSecret)
        XCTAssertEqual(captured.primaryContentType, .plainText)

        let reloadedStore = fixture.makeStore()
        let reloadedManager = await fixture.makeManager(
            pasteboard: FakePasteboard(changeCount: 0, stringValue: nil),
            store: reloadedStore
        )
        let reloaded = try XCTUnwrap(reloadedManager.items.first)
        XCTAssertEqual(reloaded.content, plainText)
        XCTAssertEqual(reloaded.primaryContentType, .plainText)
        let reloadedPayloads = await reloadedStore.payloads(for: reloaded.id)
        XCTAssertEqual(reloadedPayloads.map(\.data), [Data(plainText.utf8)])

        let encryptedValues = try encryptedClipboardValues(in: fixture.databaseURL)
        XCTAssertEqual(encryptedValues.count, 2)
        XCTAssertFalse(encryptedValues.contains { $0 == plainText || $0.contains(plainText) })
    }

    func testRealSQLitePersistenceRoundTripsMixedImageAndFileURLPayloads() async throws {
        let fixture = try makeRealPersistenceFixture()
        defer { fixture.cleanup() }
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let manager = await fixture.makeManager(pasteboard: pasteboard)
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let fileURL = "file:///Users/example/Desktop/cleanshot.png"

        pasteboard.writeDataByType(
            [.png: imageData],
            stringsByType: [.fileURL: fileURL],
            types: [.fileURL, .png]
        )
        await manager.pollClipboardForTests()

        XCTAssertEqual(manager.items.first?.content, "画像")
        XCTAssertEqual(manager.items.first?.primaryContentType, .image)

        let reloadedStore = fixture.makeStore()
        let reloadedManager = await fixture.makeManager(
            pasteboard: FakePasteboard(changeCount: 0, stringValue: nil),
            store: reloadedStore
        )
        let reloaded = try XCTUnwrap(reloadedManager.items.first)
        let payloads = await reloadedStore.payloads(for: reloaded.id)
        XCTAssertEqual(reloaded.content, "画像")
        XCTAssertEqual(reloaded.primaryContentType, .image)
        XCTAssertEqual(payloads.map(\.contentType), [.image, .fileURL])
        XCTAssertEqual(payloads.map(\.pasteboardType), [.png, .fileURL])
        XCTAssertEqual(payloads.map(\.rank), [0, 1])
        XCTAssertEqual(payloads.map(\.data), [imageData, Data(fileURL.utf8)])

        let encryptedValues = try encryptedClipboardValues(in: fixture.databaseURL)
        XCTAssertEqual(encryptedValues.count, 3)
        XCTAssertFalse(encryptedValues.contains { $0 == fileURL || $0.contains(fileURL) })
    }

    func testRealSQLitePersistencePreservesSecretClassificationAcrossLoad() async throws {
        let fixture = try makeRealPersistenceFixture()
        defer { fixture.cleanup() }
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let manager = await fixture.makeManager(pasteboard: pasteboard)
        let secretText = "token=abc123DEF456!@#7890"

        pasteboard.write(secretText)
        await manager.pollClipboardForTests()

        let captured = try XCTUnwrap(manager.items.first)
        XCTAssertEqual(captured.content, secretText)
        XCTAssertTrue(captured.isSecret)

        let reloadedStore = fixture.makeStore()
        let reloadedManager = await fixture.makeManager(
            pasteboard: FakePasteboard(changeCount: 0, stringValue: nil),
            store: reloadedStore
        )
        let reloaded = try XCTUnwrap(reloadedManager.items.first)
        XCTAssertEqual(reloaded.content, secretText)
        XCTAssertTrue(reloaded.isSecret)
        XCTAssertEqual(DashboardContentScope.inferredScope(for: reloaded), .privateItems)

        let encryptedValues = try encryptedClipboardValues(in: fixture.databaseURL)
        XCTAssertEqual(encryptedValues.count, 2)
        XCTAssertFalse(encryptedValues.contains { $0 == secretText || $0.contains(secretText) })
    }

    func testFileURLOnlyPasteboardChangeSavesSafePreviewAndPayload() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("file:///Users/example/Documents/report.pdf", types: [.fileURL])
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "ファイル: report.pdf")
        XCTAssertEqual(manager.items.first?.primaryContentType, .fileURL)
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.contentType), [.fileURL])
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.pasteboardType), [.fileURL])
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testRichTextAndHTMLPasteboardChangePreservesPayloads() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let rtfData = Data("{\\rtf1 rich}".utf8)
        let htmlData = Data("<p>rich</p>".utf8)

        pasteboard.writeDataByType(
            [.rtf: rtfData, .html: htmlData],
            stringsByType: [.string: "rich"],
            types: [.rtf, .html, .string]
        )
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.first?.content, "rich")
        XCTAssertEqual(manager.items.first?.primaryContentType, .rtf)
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.contentType), [.rtf, .html, .plainText])
        XCTAssertEqual(store.savedPayloadsForFirstItem().map(\.data), [rtfData, htmlData, Data("rich".utf8)])
    }

    func testUnsupportedPasteboardTypeIsReportedButNotSaved() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.writeTypes([NSPasteboard.PasteboardType(rawValue: "com.example.custom")])
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .unsupportedContentSkipped)
        XCTAssertEqual(manager.diagnostics.lastSaveError, "com.example.custom")
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    func testEmptyStringIsIgnored() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.items.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .emptyStringIgnored)
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    func testDuplicateLatestValueIsRecordedAsCaptureCount() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("duplicate")
        await manager.pollClipboardForTests()
        pasteboard.write("duplicate")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 1)
        XCTAssertEqual(manager.items.count, 1)
        XCTAssertEqual(store.savedItems.first?.captureCount, 2)
        XCTAssertEqual(manager.items.first?.captureCount, 2)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .duplicateRecorded)
        XCTAssertEqual(feedbackEvents, [.externalCaptureSaved])
    }

    func testNonAdjacentDuplicateValueUpdatesOriginalCaptureCountAndRecency() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("duplicate")
        await manager.pollClipboardForTests()
        pasteboard.write("intermediate")
        await manager.pollClipboardForTests()
        pasteboard.write("duplicate")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 2)
        XCTAssertEqual(manager.items.map(\.content), ["duplicate", "intermediate"])
        XCTAssertEqual(manager.items.first?.captureCount, 2)
        XCTAssertEqual(manager.items.last?.captureCount, 1)
    }

    func testSameContentFromDifferentSourceDoesNotCollapse() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        store.seedItems([
            ClipboardItem(
                id: UUID(),
                content: "shared value",
                timestamp: Date(timeIntervalSince1970: 1),
                bundleID: "com.example.first"
            )
        ])
        let manager = await makeManager(
            pasteboard: pasteboard,
            store: store,
            workspace: FakeFrontmostApplicationProvider(bundleID: "com.example.second")
        )

        pasteboard.write("shared value")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 2)
        XCTAssertEqual(manager.items.filter { $0.content == "shared value" }.count, 2)
        XCTAssertTrue(manager.items.allSatisfy { $0.captureCount == 1 })
    }

    func testSameContentWithDifferentPrimaryTypeDoesNotCollapse() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        store.seedItems([
            ClipboardItem(
                id: UUID(),
                content: "rich value",
                timestamp: Date(timeIntervalSince1970: 1),
                bundleID: "com.example.app",
                primaryContentType: .rtf
            )
        ])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("rich value")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 2)
        XCTAssertEqual(manager.items.filter { $0.content == "rich value" }.count, 2)
        XCTAssertEqual(Set(manager.items.map(\.primaryContentType)), [.plainText, .rtf])
    }

    func testSecretDuplicateCollapsesByRawContentNotMaskedPreview() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("secret-token-one")
        await manager.pollClipboardForTests()
        pasteboard.write("secret-token-two")
        await manager.pollClipboardForTests()
        pasteboard.write("secret-token-one")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 2)
        XCTAssertEqual(manager.items.first(where: { $0.content == "secret-token-one" })?.captureCount, 2)
        XCTAssertEqual(manager.items.first(where: { $0.content == "secret-token-two" })?.captureCount, 1)
        XCTAssertTrue(manager.items.allSatisfy(\.isSecret))
    }

    func testVisibleItemsFiltersByContent() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("first apple")
        await manager.pollClipboardForTests()
        pasteboard.write("second banana")
        await manager.pollClipboardForTests()

        manager.searchQuery = "apple"

        XCTAssertEqual(manager.visibleItems.map(\.content), ["first apple"])
    }

    func testVisibleItemsFiltersByBundleID() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("editor text")
        await manager.pollClipboardForTests()

        manager.searchQuery = "example.app"

        XCTAssertEqual(manager.visibleItems.map(\.content), ["editor text"])
    }

    func testSourceBundleIDsAreUniqueAndSortedByDisplayName() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        manager.items = [
            ClipboardItem(id: UUID(), content: "one", timestamp: Date(), bundleID: "com.example.zeta"),
            ClipboardItem(id: UUID(), content: "two", timestamp: Date(), bundleID: "com.example.alpha"),
            ClipboardItem(id: UUID(), content: "three", timestamp: Date(), bundleID: "com.example.alpha"),
            ClipboardItem(id: UUID(), content: "four", timestamp: Date())
        ]

        XCTAssertEqual(manager.sourceBundleIDs, ["com.example.alpha", "com.example.zeta"])
    }

    func testVisibleItemsFiltersBySelectedSourceApp() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        manager.items = [
            ClipboardItem(id: UUID(), content: "browser text", timestamp: Date(), bundleID: "com.example.browser"),
            ClipboardItem(id: UUID(), content: "editor text", timestamp: Date(), bundleID: "com.example.editor")
        ]

        manager.sourceAppFilter = "com.example.editor"

        XCTAssertEqual(manager.visibleItems.map(\.content), ["editor text"])
    }

    func testVisibleItemsFiltersOnePasswordSourceWithLongSecretLikeText() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let onePasswordContent = String(repeating: "AbCdEfGhIjKlMnOpQrStUvWxYz0123456789", count: 3)
        manager.items = [
            ClipboardItem(
                id: UUID(),
                content: onePasswordContent,
                timestamp: Date(),
                bundleID: "com.1password.1password",
                isSecret: true
            ),
            ClipboardItem(id: UUID(), content: "regular note", timestamp: Date(), bundleID: "com.example.editor")
        ]

        manager.sourceAppFilter = "com.1password.1password"

        XCTAssertEqual(manager.visibleItems.map(\.content), [onePasswordContent])
        XCTAssertEqual(manager.sourceAppDisplayName(for: "com.1password.1password"), "1PASSWORD")
    }

    func testVisibleItemsCombinesSearchAndSourceAppFilter() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        manager.items = [
            ClipboardItem(id: UUID(), content: "apple note", timestamp: Date(), bundleID: "com.example.browser"),
            ClipboardItem(id: UUID(), content: "apple draft", timestamp: Date(), bundleID: "com.example.editor"),
            ClipboardItem(id: UUID(), content: "banana draft", timestamp: Date(), bundleID: "com.example.editor")
        ]

        manager.searchQuery = "apple"
        manager.sourceAppFilter = "com.example.editor"

        XCTAssertEqual(manager.visibleItems.map(\.content), ["apple draft"])
    }

    func testVisibleItemsFiltersBySelectedFolder() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let folder = store.seedFolder(named: "Projects")
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let first = ClipboardItem(id: UUID(), content: "foldered", timestamp: Date())
        let second = ClipboardItem(id: UUID(), content: "loose", timestamp: Date())
        manager.items = [first, second]
        store.assignments[first.id] = [folder.id]
        await manager.refreshFolders()

        manager.selectedFolder = .folder(folder.id)

        XCTAssertEqual(manager.visibleItems.map(\.content), ["foldered"])
    }

    func testVisibleItemsFiltersUnfiledItems() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let folder = store.seedFolder(named: "Projects")
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let first = ClipboardItem(id: UUID(), content: "foldered", timestamp: Date())
        let second = ClipboardItem(id: UUID(), content: "loose", timestamp: Date())
        manager.items = [first, second]
        store.assignments[first.id] = [folder.id]
        await manager.refreshFolders()

        manager.selectedFolder = .unfiled

        XCTAssertEqual(manager.visibleItems.map(\.content), ["loose"])
    }

    func testVisibleItemsFiltersFavoritesIndependentlyOfFolders() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let folder = store.seedFolder(named: "Projects")
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let favoriteFoldered = ClipboardItem(id: UUID(), content: "favorite foldered", timestamp: Date(), isFavorite: true)
        let normalFoldered = ClipboardItem(id: UUID(), content: "normal foldered", timestamp: Date())
        let favoriteLoose = ClipboardItem(id: UUID(), content: "favorite loose", timestamp: Date(), isFavorite: true)
        manager.items = [favoriteFoldered, normalFoldered, favoriteLoose]
        store.assignments[favoriteFoldered.id] = [folder.id]
        store.assignments[normalFoldered.id] = [folder.id]
        await manager.refreshFolders()

        manager.selectedFolder = .folder(folder.id)
        manager.isFavoritesOnly = true

        XCTAssertEqual(manager.visibleItems.map(\.content), ["favorite foldered"])
    }

    func testToggleFavoriteUpdatesManagerAndStore() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let item = ClipboardItem(id: UUID(), content: "favorite me", timestamp: Date())
        manager.items = [item]
        store.seedItems([item])

        await manager.toggleFavorite(for: item)

        XCTAssertEqual(manager.items.first?.isFavorite, true)
        XCTAssertEqual(store.savedItems.first?.isFavorite, true)

        let updated = try XCTUnwrap(manager.items.first)
        await manager.toggleFavorite(for: updated)

        XCTAssertEqual(manager.items.first?.isFavorite, false)
        XCTAssertEqual(store.savedItems.first?.isFavorite, false)
    }

    func testUpdateDisplayTitleNormalizesAndDoesNotChangeCopiedContent() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let item = ClipboardItem(id: UUID(), content: "private clipboard value", timestamp: Date(), isSecret: true)
        manager.items = [item]
        store.seedItems([item])

        let didUpdateTitle = await manager.updateDisplayTitle(for: item, title: "  API credential  ")
        XCTAssertTrue(didUpdateTitle)
        XCTAssertEqual(manager.items.first?.displayTitle, "API credential")
        XCTAssertEqual(store.savedItems.first?.displayTitle, "API credential")

        let titledItem = try XCTUnwrap(manager.items.first)
        await manager.copyToClipboard(titledItem)
        XCTAssertEqual(pasteboard.stringValue, "private clipboard value")

        let didClearTitle = await manager.updateDisplayTitle(for: titledItem, title: "   ")
        XCTAssertTrue(didClearTitle)
        XCTAssertNil(manager.items.first?.displayTitle)
        XCTAssertNil(store.savedItems.first?.displayTitle)
    }

    func testDashboardContentScopeClassifiesExistingItems() async {
        let text = ClipboardItem(id: UUID(), content: "plain clipboard text", timestamp: Date())
        let link = ClipboardItem(id: UUID(), content: "https://example.com/docs", timestamp: Date())
        let code = ClipboardItem(id: UUID(), content: "struct ForkclipView { let title = \"Forkclip\" }", timestamp: Date())
        let image = ClipboardItem(id: UUID(), content: "画像", timestamp: Date(), primaryContentType: .image)
        let file = ClipboardItem(id: UUID(), content: "ファイル: report.pdf", timestamp: Date(), primaryContentType: .fileURL)
        let rich = ClipboardItem(id: UUID(), content: "リッチテキスト", timestamp: Date(), primaryContentType: .rtf)
        let secret = ClipboardItem(id: UUID(), content: "token-value", timestamp: Date(), isSecret: true)

        XCTAssertTrue(DashboardContentScope.text.matches(text))
        XCTAssertTrue(DashboardContentScope.links.matches(link))
        XCTAssertTrue(DashboardContentScope.code.matches(code))
        XCTAssertTrue(DashboardContentScope.images.matches(image))
        XCTAssertFalse(DashboardContentScope.files.matches(image))
        XCTAssertTrue(DashboardContentScope.files.matches(file))
        XCTAssertTrue(DashboardContentScope.richContent.matches(rich))
        XCTAssertTrue(DashboardContentScope.privateItems.matches(secret))
        XCTAssertEqual(DashboardContentScope.inferredScope(for: image), .images)
        XCTAssertEqual(DashboardContentScope.inferredScope(for: file), .files)
        XCTAssertEqual(DashboardContentScope.inferredScope(for: rich), .richContent)
        XCTAssertEqual(DashboardContentScope.inferredScope(for: secret), .privateItems)
        XCTAssertEqual(DashboardFormatters.typeSummary(for: image), "画像")
        XCTAssertEqual(DashboardFormatters.typeSummary(for: file), "ファイル")
        XCTAssertEqual(DashboardFormatters.typeSummary(for: rich), "リッチ")
        XCTAssertEqual(DashboardFormatters.captureSummary(for: text), "-")
        XCTAssertEqual(DashboardFormatters.captureSummary(for: ClipboardItem(id: UUID(), content: "repeat", timestamp: Date(), captureCount: 3)), "3 回")
    }

    func testDashboardContentScopeComposesWithManagerVisibleItems() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let link = ClipboardItem(
            id: UUID(),
            content: "https://forkclip.example/docs",
            timestamp: Date(),
            bundleID: "com.example.browser",
            isFavorite: true
        )
        let code = ClipboardItem(
            id: UUID(),
            content: "struct ForkclipView { var body: some View { Text(\"Forkclip\") } }",
            timestamp: Date(),
            bundleID: "com.example.editor"
        )
        manager.items = [link, code]
        manager.searchQuery = "forkclip"
        manager.sourceAppFilter = "com.example.browser"
        manager.isFavoritesOnly = true

        let dashboardItems = DashboardContentScope.links.filteredItems(from: manager.visibleItems)

        XCTAssertEqual(dashboardItems.map(\.content), ["https://forkclip.example/docs"])
    }

    func testDashboardCopyUsesExistingManagerCopyBehavior() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let item = ClipboardItem(id: UUID(), content: "copy from dashboard", timestamp: Date())
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        await manager.copyToClipboard(item)

        XCTAssertEqual(pasteboard.stringValue, "copy from dashboard")
        XCTAssertEqual(feedbackEvents, [.appCopySucceeded])
    }

    func testFrequentItemsOrderByUsageCountAndLastUsedAt() async {
        let older = Date(timeIntervalSince1970: 10)
        let newer = Date(timeIntervalSince1970: 20)
        let unused = ClipboardItem(id: UUID(), content: "unused", timestamp: Date(timeIntervalSince1970: 4))
        let lowUse = ClipboardItem(id: UUID(), content: "low", timestamp: Date(timeIntervalSince1970: 3), usageCount: 1, lastUsedAt: newer)
        let highOld = ClipboardItem(id: UUID(), content: "high old", timestamp: Date(timeIntervalSince1970: 2), usageCount: 3, lastUsedAt: older)
        let highNew = ClipboardItem(id: UUID(), content: "high new", timestamp: Date(timeIntervalSince1970: 1), usageCount: 3, lastUsedAt: newer)

        let ordered = DashboardFrequentItems.orderedItems(from: [unused, lowUse, highOld, highNew], limit: 3)

        XCTAssertEqual(ordered.map(\.content), ["high new", "high old", "low"])
    }

    func testSelectedItemsCanBeMovedToFolderInBatch() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let folder = store.seedFolder(named: "Projects")
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let first = ClipboardItem(id: UUID(), content: "one", timestamp: Date())
        let second = ClipboardItem(id: UUID(), content: "two", timestamp: Date())
        manager.items = [first, second]
        await manager.refreshFolders()

        manager.toggleSelection(for: first)
        manager.toggleSelection(for: second)
        await manager.assignSelectedItems(to: folder)

        XCTAssertEqual(store.assignments[first.id], [folder.id])
        XCTAssertEqual(store.assignments[second.id], [folder.id])
    }

    func testDeleteSelectedItemsRemovesItemsAndAssignments() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let folder = store.seedFolder(named: "Projects")
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let first = ClipboardItem(id: UUID(), content: "one", timestamp: Date())
        let second = ClipboardItem(id: UUID(), content: "two", timestamp: Date())
        manager.items = [first, second]
        store.seedItems([first, second])
        store.assignments[first.id] = [folder.id]
        await manager.refreshFolders()

        manager.toggleSelection(for: first)
        await manager.deleteSelectedItems()

        XCTAssertEqual(manager.items.map(\.content), ["two"])
        XCTAssertEqual(store.savedItems.map(\.content), ["two"])
        XCTAssertNil(store.assignments[first.id])
        XCTAssertTrue(manager.selectedItemIDs.isEmpty)
    }

    func testVisibleItemsReturnsAllItemsForWhitespaceSearch() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("one")
        await manager.pollClipboardForTests()
        pasteboard.write("two")
        await manager.pollClipboardForTests()
        manager.searchQuery = "   "

        XCTAssertEqual(manager.visibleItems.map(\.content), ["two", "one"])
    }

    func testPrivateModeDoesNotSaveClipboardChanges() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        manager.isPrivateMode = true
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("private text")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.items.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .privateModeSkipped)
        XCTAssertEqual(pasteboard.payloadReadCount, 0)
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    func testMonitorStartStopLifecycleUsesManualScheduler() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let scheduler = ManualClipboardMonitorScheduler()
        let manager = await makeManager(pasteboard: pasteboard, store: store, monitorScheduler: scheduler)

        manager.startMonitoring()

        XCTAssertEqual(scheduler.scheduledInterval, 0.5)
        XCTAssertTrue(scheduler.isScheduled)

        manager.stopMonitoring()

        XCTAssertFalse(scheduler.isScheduled)
        XCTAssertEqual(scheduler.invalidateCount, 1)
    }

    func testMonitorRepeatedTickWithoutChangeDoesNotSave() async {
        let pasteboard = FakePasteboard(changeCount: 7, stringValue: "initial")
        let store = FakeClipboardStore()
        let scheduler = ManualClipboardMonitorScheduler()
        let manager = await makeManager(pasteboard: pasteboard, store: store, monitorScheduler: scheduler)
        manager.startMonitoring()

        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .notRun)
    }

    func testMonitorRapidChangeCountUpdatesDoNotDuplicateSaves() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let scheduler = ManualClipboardMonitorScheduler()
        let manager = await makeManager(pasteboard: pasteboard, store: store, monitorScheduler: scheduler)
        manager.startMonitoring()

        pasteboard.write("first")
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        pasteboard.write("second")
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        XCTAssertEqual(store.savedItems.map(\.content), ["first", "second"])
        XCTAssertEqual(manager.items.map(\.content), ["second", "first"])
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testMonitorSelfCopyIgnoreAllowsLaterExternalChange() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let scheduler = ManualClipboardMonitorScheduler()
        let manager = await makeManager(pasteboard: pasteboard, store: store, monitorScheduler: scheduler)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }
        manager.startMonitoring()

        await manager.copyToClipboard(ClipboardItem(id: UUID(), content: "self-copy", timestamp: Date()))
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .selfCopyIgnored)

        pasteboard.write("external")
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        XCTAssertEqual(store.savedItems.map(\.content), ["external"])
        XCTAssertEqual(feedbackEvents, [.appCopySucceeded, .externalCaptureSaved])
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testMonitorPrivateModeToggleDoesNotReadPrivatePayload() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let scheduler = ManualClipboardMonitorScheduler()
        let manager = await makeManager(pasteboard: pasteboard, store: store, monitorScheduler: scheduler)
        manager.startMonitoring()

        manager.isPrivateMode = true
        pasteboard.write("private text")
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(pasteboard.payloadReadCount, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .privateModeSkipped)

        manager.isPrivateMode = false
        pasteboard.write("public text")
        scheduler.tick()
        await manager.waitForClipboardProcessingForTests()

        XCTAssertEqual(store.savedItems.map(\.content), ["public text"])
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveSucceeded)
    }

    func testCopyToClipboardIgnoresSelfTriggeredChange() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        await manager.copyToClipboard(ClipboardItem(id: UUID(), content: "self-copy", timestamp: Date()))
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .selfCopyIgnored)
        XCTAssertEqual(feedbackEvents, [.appCopySucceeded])
    }

    func testCopyToClipboardIncrementsUsageCountOnceOnSuccessfulCopy() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "reuse me", timestamp: Date())
        store.seedItems([item])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        await manager.copyToClipboard(item)

        XCTAssertEqual(store.savedItems.first?.usageCount, 1)
        XCTAssertNotNil(store.savedItems.first?.lastUsedAt)
        XCTAssertEqual(store.savedItems.first?.captureCount, 1)
        XCTAssertEqual(manager.items.first?.usageCount, 1)
        XCTAssertNotNil(manager.items.first?.lastUsedAt)
        XCTAssertEqual(manager.items.first?.captureCount, 1)
    }

    func testCopyPlainTextToClipboardIncrementsOriginalUsageCount() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "  reuse me  ", timestamp: Date(), primaryContentType: .rtf)
        store.seedItems([item])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        await manager.copyPlainTextToClipboard(from: item)

        XCTAssertEqual(pasteboard.stringValue, "reuse me")
        XCTAssertEqual(store.savedItems.first?.usageCount, 1)
        XCTAssertNotNil(store.savedItems.first?.lastUsedAt)
        XCTAssertEqual(manager.items.first?.usageCount, 1)
        XCTAssertNotNil(manager.items.first?.lastUsedAt)
    }

    func testCopyToClipboardDoesNotEmitFeedbackWhenPasteboardWriteFails() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        pasteboard.setStringResult = false
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "copy failure", timestamp: Date())
        store.seedItems([item])
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        await manager.copyToClipboard(item)

        XCTAssertTrue(feedbackEvents.isEmpty)
        XCTAssertEqual(store.savedItems.first?.usageCount, 0)
        XCTAssertNil(store.savedItems.first?.lastUsedAt)
    }

    func testCopyToClipboardDoesNotAutoPasteByDefault() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let autoPaste = FakeAutoPasteCoordinator()
        let item = ClipboardItem(id: UUID(), content: "manual copy", timestamp: Date())
        store.seedItems([item])
        autoPaste.target = AutoPasteTarget(processIdentifier: 42, bundleIdentifier: "com.example.editor", localizedName: "Editor")
        let manager = await makeManager(pasteboard: pasteboard, store: store, autoPasteCoordinator: autoPaste)
        manager.captureAutoPasteTarget()

        await manager.copyToClipboard(item)

        XCTAssertEqual(pasteboard.stringValue, "manual copy")
        XCTAssertTrue(autoPaste.pastedTargets.isEmpty)
    }

    func testCopyToClipboardAutoPasteAttemptsCapturedTargetAfterCopy() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let autoPaste = FakeAutoPasteCoordinator()
        let item = ClipboardItem(id: UUID(), content: "auto paste", timestamp: Date())
        let target = AutoPasteTarget(processIdentifier: 42, bundleIdentifier: "com.example.editor", localizedName: "Editor")
        store.seedItems([item])
        autoPaste.target = target
        let manager = await makeManager(pasteboard: pasteboard, store: store, autoPasteCoordinator: autoPaste)
        manager.captureAutoPasteTarget()

        await manager.copyToClipboard(item, autoPaste: true)

        XCTAssertEqual(pasteboard.stringValue, "auto paste")
        XCTAssertEqual(autoPaste.pastedTargets, [target])
        XCTAssertNil(manager.bannerStatus)
    }

    func testCopyToClipboardAutoPasteFailureKeepsCopiedValueAndReportsStatus() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let autoPaste = FakeAutoPasteCoordinator()
        let item = ClipboardItem(id: UUID(), content: "copy survives", timestamp: Date())
        let target = AutoPasteTarget(processIdentifier: 42, bundleIdentifier: "com.example.editor", localizedName: "Editor")
        store.seedItems([item])
        autoPaste.target = target
        autoPaste.pasteResult = false
        let manager = await makeManager(pasteboard: pasteboard, store: store, autoPasteCoordinator: autoPaste)
        manager.captureAutoPasteTarget()

        await manager.copyToClipboard(item, autoPaste: true)

        XCTAssertEqual(pasteboard.stringValue, "copy survives")
        XCTAssertEqual(autoPaste.pastedTargets, [target])
        XCTAssertEqual(manager.bannerStatus, .autoPasteFailed(target: "Editor"))
    }

    func testCopyToClipboardWritesStoredPayloadRepresentations() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let item = ClipboardItem(id: UUID(), content: "rich fallback", timestamp: Date())
        let htmlData = Data("<strong>rich</strong>".utf8)
        store.seedItems([
            item
        ], payloads: [
            item.id: [
                ClipboardPayload(contentType: .html, pasteboardType: .html, data: htmlData, preview: "HTML", rank: 0),
                .plainText("rich fallback", rank: 1)
            ]
        ])
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        await manager.copyToClipboard(item)

        XCTAssertEqual(pasteboard.data(forType: .html), htmlData)
        XCTAssertEqual(pasteboard.string(forType: .string), "rich fallback")
        XCTAssertEqual(Set(pasteboard.availableTypes), Set([.html, .string]))
        XCTAssertEqual(feedbackEvents, [.appCopySucceeded])
    }

    func testCopyToClipboardWritesURLTextAsURLAndPlainText() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let item = ClipboardItem(id: UUID(), content: "https://example.com", timestamp: Date())
        store.seedItems([item], payloads: [
            item.id: [
                ClipboardPayload(contentType: .urlText, pasteboardType: .URL, data: Data("https://example.com".utf8), preview: "https://example.com", rank: 0)
            ]
        ])

        await manager.copyToClipboard(item)

        XCTAssertEqual(pasteboard.string(forType: .URL), "https://example.com")
        XCTAssertEqual(pasteboard.string(forType: .string), "https://example.com")
        XCTAssertEqual(Set(pasteboard.availableTypes), Set([.URL, .string]))
    }

    func testCopyToClipboardWritesImageAndFilePayloads() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let imageItem = ClipboardItem(id: UUID(), content: "画像", timestamp: Date())
        let fileItem = ClipboardItem(id: UUID(), content: "ファイル: report.pdf", timestamp: Date())
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let fileURL = "file:///Users/example/Documents/report.pdf"
        store.seedItems([imageItem, fileItem], payloads: [
            imageItem.id: [
                ClipboardPayload(contentType: .image, pasteboardType: .png, data: imageData, preview: "画像", rank: 0)
            ],
            fileItem.id: [
                ClipboardPayload(contentType: .fileURL, pasteboardType: .fileURL, data: Data(fileURL.utf8), preview: "ファイル: report.pdf", rank: 0)
            ]
        ])

        await manager.copyToClipboard(imageItem)
        XCTAssertEqual(pasteboard.data(forType: .png), imageData)

        await manager.copyToClipboard(fileItem)
        XCTAssertEqual(pasteboard.string(forType: .fileURL), fileURL)
    }

    func testImageThumbnailReturnsImageFromImagePayload() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "画像", timestamp: Date(), primaryContentType: .image)
        let imageData = try makeThumbnailPNGData()
        store.seedItems([item], payloads: [
            item.id: [
                ClipboardPayload(contentType: .image, pasteboardType: .png, data: imageData, preview: "画像", rank: 0)
            ]
        ])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        let thumbnail = manager.imageThumbnail(for: item)

        XCTAssertNotNil(thumbnail)
    }

    func testImageThumbnailReturnsNilForNonImageItem() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "plain", timestamp: Date(), primaryContentType: .plainText)
        let imageData = try makeThumbnailPNGData()
        store.seedItems([item], payloads: [
            item.id: [
                ClipboardPayload(contentType: .image, pasteboardType: .png, data: imageData, preview: "画像", rank: 0)
            ]
        ])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        XCTAssertNil(manager.imageThumbnail(for: item))
    }

    func testImageThumbnailReturnsNilForSecretImageItem() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "画像", timestamp: Date(), isSecret: true, primaryContentType: .image)
        let imageData = try makeThumbnailPNGData()
        store.seedItems([item], payloads: [
            item.id: [
                ClipboardPayload(contentType: .image, pasteboardType: .png, data: imageData, preview: "画像", rank: 0)
            ]
        ])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        XCTAssertNil(manager.imageThumbnail(for: item))
    }

    func testImageThumbnailReturnsNilForInvalidImagePayload() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let item = ClipboardItem(id: UUID(), content: "画像", timestamp: Date(), primaryContentType: .image)
        store.seedItems([item], payloads: [
            item.id: [
                ClipboardPayload(contentType: .image, pasteboardType: .png, data: Data("not image data".utf8), preview: "画像", rank: 0)
            ]
        ])
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        XCTAssertNil(manager.imageThumbnail(for: item))
    }

    func testDeleteRemovesItemFromManagerAndStore() async throws {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("delete me")
        await manager.pollClipboardForTests()
        let item = try XCTUnwrap(manager.items.first)

        await manager.delete(item)

        XCTAssertEqual(manager.items.count, 0)
        XCTAssertEqual(store.savedItems.count, 0)
    }

    func testDeleteStillRemovesFavoriteItem() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        let item = ClipboardItem(id: UUID(), content: "delete favorite", timestamp: Date(), isFavorite: true)
        manager.items = [item]
        store.seedItems([item])

        await manager.delete(item)

        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertTrue(store.savedItems.isEmpty)
    }

    func testBlacklistedApplicationIsIgnored() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let security = FakeSecurityProvider()
        let workspace = FakeFrontmostApplicationProvider(bundleID: "com.agilebits.onepassword")
        let manager = await makeManager(
            pasteboard: pasteboard,
            store: store,
            security: security,
            workspace: workspace
        )
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("secret value")
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .blacklistedApplicationIgnored)
        XCTAssertEqual(pasteboard.payloadReadCount, 0)
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    func testConcealedPasteboardTypeIsIgnoredWithoutReadingPayload() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("concealed secret", types: [.string, ClipboardPasteboardMetadata.concealedType])
        await manager.pollClipboardForTests()

        XCTAssertEqual(store.savedItems.count, 0)
        XCTAssertEqual(manager.items.count, 0)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .concealedContentSkipped)
        XCTAssertEqual(manager.diagnostics.lastSaveError, ClipboardPasteboardMetadata.concealedType.rawValue)
        XCTAssertEqual(pasteboard.payloadReadCount, 0)
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    func testSaveFailureDoesNotEmitFeedback() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        store.saveResult = false
        store.saveError = .databaseUnavailable
        let security = FakeSecurityProvider()
        security.lastError = .keyMissing
        let manager = await makeManager(pasteboard: pasteboard, store: store, security: security)
        var feedbackEvents: [ClipboardFeedbackEvent] = []
        manager.feedbackHandler = { feedbackEvents.append($0) }

        pasteboard.write("will fail")
        await manager.pollClipboardForTests()

        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveFailed)
        XCTAssertEqual(manager.diagnostics.lastSaveError, ClipboardPersistenceError.databaseUnavailable.localizedDescription)
        XCTAssertNotEqual(manager.diagnostics.lastSaveError, SecurityManager.SecurityError.keyMissing.localizedDescription)
        XCTAssertTrue(feedbackEvents.isEmpty)
    }

    func testEncryptionSaveFailureReportsSecurityFailure() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        store.saveResult = false
        store.saveError = .itemEncryptionFailed(.keyMissing)
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        pasteboard.write("will fail encryption")
        await manager.pollClipboardForTests()

        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .saveFailed)
        XCTAssertEqual(manager.diagnostics.lastSaveError, SecurityManager.SecurityError.keyMissing.localizedDescription)
    }

    func testRecoverFromMissingKeyReportsSuccess() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        await manager.recoverFromMissingKey()

        XCTAssertEqual(store.recoverCallCount, 1)
        XCTAssertEqual(manager.recoveryStatus, .succeeded)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .recoverySucceeded)
        XCTAssertNil(manager.diagnostics.lastSaveError)
    }

    func testRecoverFromMissingKeyReportsFailure() async {
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        store.recoverResult = false
        let security = FakeSecurityProvider()
        security.lastError = .keyMissing
        let manager = await makeManager(pasteboard: pasteboard, store: store, security: security)

        await manager.recoverFromMissingKey()

        XCTAssertEqual(store.recoverCallCount, 1)
        XCTAssertEqual(manager.recoveryStatus, .failed)
        XCTAssertEqual(manager.diagnostics.lastSaveStatus, .recoveryFailed)
        XCTAssertEqual(manager.diagnostics.lastSaveError, SecurityManager.SecurityError.keyMissing.localizedDescription)
    }

    func testAppPathsUseForkclipCleanStartIdentity() async throws {
        let appSupportDirectory = try AppPaths.applicationSupportDirectory()
        let databaseURL = try AppPaths.databaseURL()

        XCTAssertEqual(appSupportDirectory.lastPathComponent, "Forkclip")
        XCTAssertEqual(databaseURL.lastPathComponent, "forkclip.sqlite")
        XCTAssertEqual(databaseURL.deletingLastPathComponent(), appSupportDirectory)
    }

    func testClipboardStatusFormatterDocumentsReviewedJapaneseCopy() {
        XCTAssertEqual(ClipboardStatusFormatter.databaseText(.available), "利用可能")
        XCTAssertEqual(ClipboardStatusFormatter.databaseText(.failed), "利用不可")
        XCTAssertEqual(ClipboardStatusFormatter.keyText(.missing), "見つかりません")
        XCTAssertEqual(ClipboardStatusFormatter.keyText(.failed), "確認失敗")
        XCTAssertEqual(ClipboardStatusFormatter.monitorText(.monitoring), "監視中")
        XCTAssertEqual(ClipboardStatusFormatter.operationText(.privateModeSkipped), "プライベートモードで未保存")
        XCTAssertEqual(ClipboardStatusFormatter.operationText(.blacklistedApplicationIgnored), "除外アプリのため未保存")
        XCTAssertEqual(ClipboardStatusFormatter.operationText(.concealedContentSkipped), "機微マーカー付きのため未保存")
        XCTAssertEqual(ClipboardStatusFormatter.operationText(.unsupportedContentSkipped), "未対応形式のため未保存")
        XCTAssertEqual(ClipboardStatusFormatter.operationText(.duplicateRecorded), "重複を記録")
        XCTAssertEqual(ClipboardStatusFormatter.operationText(.saveFailed), "保存失敗")
        XCTAssertEqual(
            ClipboardStatusFormatter.bannerText(.saveFailed(detail: "database unavailable")),
            "クリップボードの保存に失敗しました。database unavailable"
        )
        XCTAssertEqual(
            ClipboardStatusFormatter.bannerText(.keyProblem(detail: nil)),
            "暗号鍵を確認できません。Keychain の状態を確認してください。"
        )
        XCTAssertEqual(
            ClipboardStatusFormatter.bannerText(.fetchFailures(count: 2, detail: nil)),
            "復号できない履歴が 2 件あります。暗号鍵または保存データを確認してください。"
        )
        XCTAssertEqual(
            ClipboardStatusFormatter.recoveryText(.succeeded),
            "既存 DB をバックアップし、新しい暗号鍵で初期化しました。"
        )
        XCTAssertEqual(ClipboardStatusFormatter.folderText(.assignFailed), "フォルダへ移動できませんでした。")
    }

    func testClipboardStatusFormatterPreservesDiagnosticsDateAndTime() {
        let date = Date(timeIntervalSince1970: 1_721_234_567)
        let text = ClipboardStatusFormatter.diagnosticsProcessedAtText(date)

        XCTAssertEqual(ClipboardStatusFormatter.diagnosticsProcessedAtText(nil), "未処理")
        XCTAssertNotNil(text.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#, options: .regularExpression))
    }

    func testFocusedStatesDriveFilteringFoldersSelectionDiagnosticsFavoritesAndUsage() async {
        let folderedID = UUID()
        let favoriteID = UUID()
        let foldered = ClipboardItem(
            id: folderedID,
            content: "Project note",
            timestamp: Date(timeIntervalSince1970: 2),
            bundleID: "com.example.notes"
        )
        let favorite = ClipboardItem(
            id: favoriteID,
            content: "Favorite code",
            timestamp: Date(timeIntervalSince1970: 1),
            bundleID: "com.example.editor",
            isFavorite: true
        )
        let pasteboard = FakePasteboard(changeCount: 0, stringValue: nil)
        let store = FakeClipboardStore()
        let folder = store.seedFolder(named: "Work")
        store.seedItems([foldered, favorite])
        store.assignments = [folderedID: [folder.id]]
        store.lastFetchFailureCount = 1
        let manager = await makeManager(pasteboard: pasteboard, store: store)

        XCTAssertEqual(manager.historyState.items.map(\.id), [folderedID, favoriteID])
        XCTAssertEqual(manager.folderState.folders.map(\.id), [folder.id])
        XCTAssertEqual(manager.folderState.folderName(for: .folder(folder.id)), "Work")
        XCTAssertEqual(manager.folderState.folderIDs(for: foldered), [folder.id])

        manager.historyState.searchQuery = "favorite"
        XCTAssertEqual(manager.visibleItems.map(\.id), [favoriteID])

        manager.historyState.searchQuery = ""
        manager.folderState.selectedFolder = .unfiled
        XCTAssertEqual(manager.visibleItems.map(\.id), [favoriteID])

        manager.historyState.isFavoritesOnly = true
        XCTAssertEqual(manager.visibleItems.map(\.id), [favoriteID])
        await manager.toggleFavorite(for: favorite)
        XCTAssertEqual(manager.historyState.items.first(where: { $0.id == favoriteID })?.isFavorite, false)

        manager.selectionState.toggleSelection(for: foldered)
        XCTAssertEqual(manager.selectionState.selectedItemIDs, [folderedID])
        manager.selectionState.clearSelection()
        XCTAssertTrue(manager.selectionState.selectedItemIDs.isEmpty)

        await manager.refreshDiagnostics()
        XCTAssertEqual(manager.diagnosticsState.diagnostics.fetchFailureCount, 1)

        await manager.copyToClipboard(foldered)
        XCTAssertEqual(manager.historyState.items.first(where: { $0.id == folderedID })?.usageCount, 1)
        XCTAssertNotNil(manager.historyState.items.first(where: { $0.id == folderedID })?.lastUsedAt)
    }

    private func makeManager(
        pasteboard: FakePasteboard,
        store: FakeClipboardStore,
        security: SecurityProviding = FakeSecurityProvider(),
        workspace: FakeFrontmostApplicationProvider = FakeFrontmostApplicationProvider(bundleID: "com.example.app"),
        autoPasteCoordinator: AutoPasteCoordinating = FakeAutoPasteCoordinator(),
        monitorScheduler: ClipboardMonitorScheduling = RunLoopClipboardMonitorScheduler()
    ) async -> ClipboardManager {
        let manager = ClipboardManager(
            pasteboard: pasteboard,
            store: store,
            security: security,
            frontmostApplicationProvider: workspace,
            initialPrivateMode: false,
            autoPasteCoordinator: autoPasteCoordinator,
            monitorScheduler: monitorScheduler
        )
        await manager.waitForInitialLoadForTests()
        return manager
    }

    private func makeRealPersistenceFixture() throws -> RealPersistenceFixture {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let databaseURL = tempDirectory.appendingPathComponent("forkclip-integration.sqlite")
        let security = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
        return RealPersistenceFixture(
            tempDirectory: tempDirectory,
            databaseURL: databaseURL,
            security: security
        )
    }

    private func encryptedClipboardValues(in databaseURL: URL) throws -> [String] {
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let itemContent = Expression<String>("content")
        let payloads = Table("clipboard_payloads")
        let encryptedData = Expression<String>("encrypted_data")
        var values = try db.prepare(items.select(itemContent)).map { $0[itemContent] }
        values.append(contentsOf: try db.prepare(payloads.select(encryptedData)).map { $0[encryptedData] })
        return values
    }

    private func makeThumbnailPNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private struct RealPersistenceFixture {
    let tempDirectory: URL
    let databaseURL: URL
    let security: SecurityManager

    func makeStore() -> DatabaseManager {
        DatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(),
            security: security
        )
    }

    func makeManager(
        pasteboard: FakePasteboard,
        store: DatabaseManager? = nil,
        workspace: FakeFrontmostApplicationProvider = FakeFrontmostApplicationProvider(bundleID: "com.example.integration")
    ) async -> ClipboardManager {
        let manager = ClipboardManager(
            pasteboard: pasteboard,
            store: store ?? makeStore(),
            security: security,
            frontmostApplicationProvider: workspace,
            initialPrivateMode: false,
            autoPasteCoordinator: FakeAutoPasteCoordinator()
        )
        await manager.waitForInitialLoadForTests()
        return manager
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempDirectory)
    }
}

@MainActor
private final class FakePasteboard: PasteboardProviding {
    var changeCount: Int
    var setStringResult = true
    var setDataResult = true
    var fallbackImageDataValue: Data?
    private(set) var stringReadCount = 0
    private(set) var dataReadCount = 0
    private(set) var fallbackImageReadCount = 0
    private var stringValues: [NSPasteboard.PasteboardType: String]
    private var dataValues: [NSPasteboard.PasteboardType: Data]
    private(set) var availableTypes: [NSPasteboard.PasteboardType]

    var stringValue: String? {
        stringValues[.string]
    }

    var payloadReadCount: Int {
        stringReadCount + dataReadCount + fallbackImageReadCount
    }

    init(changeCount: Int, stringValue: String?) {
        self.changeCount = changeCount
        self.stringValues = stringValue.map { [.string: $0] } ?? [:]
        self.dataValues = [:]
        self.availableTypes = stringValue == nil ? [] : [.string]
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        stringReadCount += 1
        if let string = stringValues[type] {
            return string
        }
        return dataValues[type].flatMap { String(data: $0, encoding: .utf8) }
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        dataReadCount += 1
        if let data = dataValues[type] {
            return data
        }
        return stringValues[type].map { Data($0.utf8) }
    }

    func fallbackImageData() -> Data? {
        fallbackImageReadCount += 1
        return fallbackImageDataValue
    }

    func clearContents() -> Int {
        stringValues.removeAll()
        dataValues.removeAll()
        fallbackImageDataValue = nil
        availableTypes = []
        changeCount += 1
        return 1
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        guard setStringResult else { return false }
        stringValues[type] = string
        dataValues.removeValue(forKey: type)
        fallbackImageDataValue = nil
        appendAvailableType(type)
        changeCount += 1
        return true
    }

    func setData(_ data: Data?, forType type: NSPasteboard.PasteboardType) -> Bool {
        guard setDataResult, let data else { return false }
        dataValues[type] = data
        stringValues.removeValue(forKey: type)
        fallbackImageDataValue = nil
        appendAvailableType(type)
        changeCount += 1
        return true
    }

    func write(_ string: String) {
        write(string, types: [.string])
    }

    func write(_ string: String, types: [NSPasteboard.PasteboardType]) {
        stringValues = Dictionary(uniqueKeysWithValues: types.map { ($0, string) })
        dataValues.removeAll()
        fallbackImageDataValue = nil
        availableTypes = types
        changeCount += 1
    }

    func writeData(_ data: Data, forType type: NSPasteboard.PasteboardType) {
        writeDataByType([type: data], types: [type])
    }

    func writeDataByType(
        _ dataByType: [NSPasteboard.PasteboardType: Data],
        stringsByType: [NSPasteboard.PasteboardType: String] = [:],
        types: [NSPasteboard.PasteboardType]? = nil
    ) {
        dataValues = dataByType
        stringValues = stringsByType
        fallbackImageDataValue = nil
        availableTypes = types ?? Array(dataByType.keys) + Array(stringsByType.keys)
        changeCount += 1
    }

    func writeImageTypeWithoutDirectData(_ type: NSPasteboard.PasteboardType, fallbackData: Data) {
        stringValues.removeAll()
        dataValues.removeAll()
        fallbackImageDataValue = fallbackData
        availableTypes = [type]
        changeCount += 1
    }

    func writeTypes(_ types: [NSPasteboard.PasteboardType]) {
        stringValues.removeAll()
        dataValues.removeAll()
        fallbackImageDataValue = nil
        availableTypes = types
        changeCount += 1
    }

    private func appendAvailableType(_ type: NSPasteboard.PasteboardType) {
        if !availableTypes.contains(type) {
            availableTypes.append(type)
        }
    }
}

@MainActor
private final class ManualClipboardMonitorScheduler: ClipboardMonitorScheduling {
    private var onTick: (@MainActor () -> Void)?
    private(set) var scheduledInterval: TimeInterval?
    private(set) var invalidateCount = 0

    var isScheduled: Bool {
        onTick != nil
    }

    func scheduleRepeating(every interval: TimeInterval, onTick: @escaping @MainActor () -> Void) -> ClipboardMonitorSchedule {
        self.scheduledInterval = interval
        self.onTick = onTick
        return ManualClipboardMonitorSchedule { [weak self] in
            self?.invalidateCount += 1
            self?.onTick = nil
        }
    }

    func tick() {
        onTick?()
    }
}

@MainActor
private final class ManualClipboardMonitorSchedule: ClipboardMonitorSchedule {
    private let onInvalidate: @MainActor () -> Void

    init(onInvalidate: @escaping @MainActor () -> Void) {
        self.onInvalidate = onInvalidate
    }

    func invalidate() {
        onInvalidate()
    }
}

private final class FakeClipboardStore: ClipboardStore, @unchecked Sendable {
    var lastFetchFailureCount = 0
    var recoverResult = true
    var saveResult = true
    var saveError: ClipboardPersistenceError = .databaseWriteFailed("Fake save failure.")
    var folders: [ClipboardFolder] = []
    var assignments: [UUID: Set<UUID>] = [:]
    private(set) var recoverCallCount = 0
    private(set) var savedItems: [ClipboardItem] = []
    private(set) var savedPayloads: [UUID: [ClipboardPayload]] = [:]

    func saveItem(_ item: ClipboardItem, originBundleID: String?, secret: Bool, migrated: Bool) async throws {
        try await saveItem(item, payloads: [.plainText(item.content)], originBundleID: originBundleID, secret: secret, migrated: migrated)
    }

    func saveItem(_ item: ClipboardItem, payloads: [ClipboardPayload], originBundleID: String?, secret: Bool, migrated: Bool) async throws {
        guard saveResult else { throw saveError }
        savedItems.append(item)
        savedPayloads[item.id] = payloads
    }

    func payloads(for itemID: UUID) async -> [ClipboardPayload] {
        savedPayloads[itemID] ?? []
    }

    func deleteItem(withID itemID: UUID) async {
        savedItems.removeAll { $0.id == itemID }
        savedPayloads.removeValue(forKey: itemID)
        assignments.removeValue(forKey: itemID)
    }

    func fetchAll() async -> [ClipboardItem] {
        savedItems.sorted { $0.lastCapturedAt > $1.lastCapturedAt }
    }

    func fetchFolders() async -> [ClipboardFolder] {
        folders
    }

    func fetchFolderAssignments() async -> [UUID: Set<UUID>] {
        assignments
    }

    func createFolder(named name: String, color: String) async -> ClipboardFolder? {
        seedFolder(named: name, color: color)
    }

    func updateFolder(_ folder: ClipboardFolder) async -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return false }
        folders[index] = folder
        return true
    }

    func deleteFolder(withID id: UUID) async {
        folders.removeAll { $0.id == id }
        assignments = assignments.mapValues { folderIDs in
            var updated = folderIDs
            updated.remove(id)
            return updated
        }
    }

    func assignItem(_ itemID: UUID, toFolder folderID: UUID) async -> Bool {
        assignments[itemID, default: []].insert(folderID)
        return true
    }

    func unassignItem(_ itemID: UUID, fromFolder folderID: UUID) async {
        assignments[itemID]?.remove(folderID)
    }

    func unassignItemFromAllFolders(_ itemID: UUID) async {
        assignments.removeValue(forKey: itemID)
    }

    func reorderFolders(_ orderedFolders: [ClipboardFolder]) async -> Bool {
        folders = orderedFolders
        return true
    }

    func updateFavoriteState(for itemID: UUID, isFavorite: Bool) async -> Bool {
        guard let index = savedItems.firstIndex(where: { $0.id == itemID }) else { return false }
        savedItems[index].isFavorite = isFavorite
        return true
    }

    func updateSecretState(for itemID: UUID, isSecret: Bool) async -> Bool {
        guard let index = savedItems.firstIndex(where: { $0.id == itemID }) else { return false }
        savedItems[index].isSecret = isSecret
        return true
    }

    func updateDisplayTitle(for itemID: UUID, displayTitle: String?) async -> Bool {
        guard let index = savedItems.firstIndex(where: { $0.id == itemID }) else { return false }
        savedItems[index].displayTitle = ClipboardItem.normalizedDisplayTitle(displayTitle)
        return true
    }

    func recordDuplicateCapture(content: String, primaryContentType: ClipboardContentType, bundleID: String?, at date: Date) async -> ClipboardItem? {
        guard let index = savedItems.firstIndex(where: {
            $0.content == content
                && $0.primaryContentType == primaryContentType
                && $0.bundleID == bundleID
        }) else {
            return nil
        }
        savedItems[index].captureCount += 1
        savedItems[index].lastCapturedAt = date
        return savedItems[index]
    }

    func recordUse(for itemID: UUID, at date: Date) async -> ClipboardItem? {
        guard let index = savedItems.firstIndex(where: { $0.id == itemID }) else { return nil }
        savedItems[index].usageCount += 1
        savedItems[index].lastUsedAt = date
        return savedItems[index]
    }

    @discardableResult
    func seedFolder(named name: String, color: String = "#4A90E2") -> ClipboardFolder {
        let folder = ClipboardFolder(name: name, color: color, sortOrder: folders.count)
        folders.append(folder)
        return folder
    }

    func seedItems(_ items: [ClipboardItem], payloads: [UUID: [ClipboardPayload]] = [:]) {
        savedItems = items
        savedPayloads = payloads
    }

    func savedPayloadsForFirstItem() -> [ClipboardPayload] {
        guard let itemID = savedItems.first?.id else { return [] }
        return savedPayloads[itemID] ?? []
    }

    func diagnosticsSnapshot() async -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            databasePath: "/tmp/test.sqlite",
            databaseStatus: .available,
            fetchFailureCount: lastFetchFailureCount,
            keyState: .available,
            securityErrorDescription: nil,
            lastRecoveryBackupPath: nil,
            monitorState: .unchecked,
            lastObservedChangeCount: nil,
            lastProcessedChangeAt: nil,
            lastSaveStatus: .notRun,
            lastSaveError: nil
        )
    }

    func recoverFromMissingKey() async -> Bool {
        recoverCallCount += 1
        return recoverResult
    }
}

@MainActor
private final class FakeAutoPasteCoordinator: AutoPasteCoordinating {
    var target: AutoPasteTarget?
    var pasteResult = true
    private(set) var captureCallCount = 0
    private(set) var pastedTargets: [AutoPasteTarget] = []

    func captureTarget() -> AutoPasteTarget? {
        captureCallCount += 1
        return target
    }

    func paste(to target: AutoPasteTarget) async -> Bool {
        pastedTargets.append(target)
        return pasteResult
    }
}

@MainActor
private final class FakeSecurityProvider: SecurityProviding {
    var lastError: SecurityManager.SecurityError?
    var blacklistedBundleIDs: Set<String> = []
    var secretDetector: (String) -> Bool = { $0.contains("secret") }

    func isApplicationBlacklisted(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        let lowerID = bundleID.lowercased()
        return blacklistedBundleIDs.contains(bundleID)
            || lowerID == "com.1password.1password"
            || lowerID.hasPrefix("com.1password.1password.")
            || lowerID == "com.agilebits.onepassword"
            || lowerID.hasPrefix("com.agilebits.onepassword.")
            || lowerID == "com.apple.keychainaccess"
            || lowerID.hasPrefix("com.apple.keychainaccess.")
    }

    func isLikelySecret(_ text: String) -> Bool {
        secretDetector(text)
    }

    func resetLastError() {
        lastError = nil
    }

    func currentKeyState() -> SecurityKeyState {
        .available
    }

    func ensureEncryptionKeyExists() -> Bool {
        true
    }
}

@MainActor
private struct FakeFrontmostApplicationProvider: FrontmostApplicationProviding {
    let bundleID: String?

    func frontmostBundleIdentifier() -> String? {
        bundleID
    }
}
#elseif canImport(Testing)
import Testing
@testable import Forkclip

@Test
func xctestCoverageSentinelClipboardManagerTestsOnMacOS() async throws {
    #expect(true)
}
#endif
