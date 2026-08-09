#if canImport(XCTest)
import XCTest
import AppKit
import SQLite
@testable import Forkclip

@MainActor
final class DatabaseManagerTests: XCTestCase {
    private let security = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())

    func testSaveItemCreatesPlainTextPayloadAndFetchesItem() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(
            id: UUID(),
            content: "hello payload",
            timestamp: Date(),
            displayTitle: "Greeting",
            bundleID: "com.example.source"
        )

        try await manager.saveItem(item, originBundleID: item.bundleID, secret: false, migrated: false)

        let fetched = await manager.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.content, "hello payload")
        XCTAssertEqual(fetched.first?.displayTitle, "Greeting")
        XCTAssertEqual(fetched.first?.bundleID, "com.example.source")
        XCTAssertEqual(fetched.first?.isFavorite, false)
        XCTAssertEqual(fetched.first?.primaryContentType, .plainText)

        let db = try Connection(databaseURL.path)
        let payloads = Table("clipboard_payloads")
        let items = Table("clipboard_items")
        let displayTitle = Expression<String?>("display_title")
        let contentType = Expression<String>("content_type")
        let primaryContentType = Expression<String>("primary_content_type")
        let duplicateDigest = Expression<String?>("duplicate_digest")
        let usageCount = Expression<Int>("usage_count")
        let lastUsedAt = Expression<Date?>("last_used_at")
        let captureCount = Expression<Int>("capture_count")
        let lastCapturedAt = Expression<Date?>("last_captured_at")
        let pasteboardType = Expression<String>("pasteboard_type")
        let encryptedData = Expression<String>("encrypted_data")
        let byteSize = Expression<Int>("byte_size")
        let preview = Expression<String?>("preview")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let row = try XCTUnwrap(db.pluck(payloads))
        let itemRow = try XCTUnwrap(db.pluck(items))

        XCTAssertEqual(itemRow[primaryContentType], ClipboardContentType.plainText.rawValue)
        let storedDuplicateDigest = try XCTUnwrap(itemRow[duplicateDigest])
        XCTAssertEqual(storedDuplicateDigest, security.duplicateContentDigest(for: "hello payload"))
        XCTAssertFalse(storedDuplicateDigest.contains("hello payload"))
        XCTAssertEqual(itemRow[usageCount], 0)
        XCTAssertNil(itemRow[lastUsedAt])
        XCTAssertEqual(itemRow[captureCount], 1)
        XCTAssertEqual(try XCTUnwrap(itemRow[lastCapturedAt]).timeIntervalSince1970, item.timestamp.timeIntervalSince1970, accuracy: 0.001)
        let encryptedDisplayTitle = try XCTUnwrap(itemRow[displayTitle])
        XCTAssertNotEqual(encryptedDisplayTitle, "Greeting")
        XCTAssertEqual(security.decrypt(encryptedDisplayTitle, context: .itemDisplayTitle(itemID: item.id)), "Greeting")
        XCTAssertEqual(fetched.first?.usageCount, 0)
        XCTAssertNil(fetched.first?.lastUsedAt)
        XCTAssertEqual(fetched.first?.captureCount, 1)
        XCTAssertEqual(try XCTUnwrap(fetched.first?.lastCapturedAt).timeIntervalSince1970, item.timestamp.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(try db.scalar(payloads.count), 1)
        XCTAssertEqual(row[contentType], ClipboardContentType.plainText.rawValue)
        XCTAssertEqual(row[pasteboardType], NSPasteboard.PasteboardType.string.rawValue)
        XCTAssertEqual(row[byteSize], "hello payload".utf8.count)
        XCTAssertNil(row[preview])
        XCTAssertNotEqual(row[encryptedData], "hello payload")
        let decryptedPayload = try XCTUnwrap(security.decrypt(
            row[encryptedData],
            context: .payloadData(itemID: row[payloadItemID], payloadID: row[payloadID])
        ))
        XCTAssertEqual(Data(base64Encoded: decryptedPayload), Data("hello payload".utf8))
    }

    func testDisplayTitleCanBeUpdatedAndCleared() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(id: UUID(), content: "private content", timestamp: Date())

        try await manager.saveItem(item, originBundleID: nil, secret: true, migrated: false)

        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let displayTitle = Expression<String?>("display_title")
        let displayTitleColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'display_title'") as? Int64 ?? 0
        XCTAssertEqual(displayTitleColumnCount, 1)
        XCTAssertNotNil(security.encrypt("API credential", context: .itemDisplayTitle(itemID: item.id)))

        let didUpdateTitle = await manager.updateDisplayTitle(for: item.id, displayTitle: "  API credential  ")
        XCTAssertTrue(didUpdateTitle)
        var fetched = await manager.fetchAll()
        XCTAssertEqual(fetched.first?.content, "private content")
        XCTAssertEqual(fetched.first?.displayTitle, "API credential")
        XCTAssertEqual(fetched.first?.isSecret, true)

        let itemRow = try XCTUnwrap(db.pluck(items.filter(id == item.id)))
        let encryptedDisplayTitle = try XCTUnwrap(itemRow[displayTitle])

        XCTAssertNotEqual(encryptedDisplayTitle, "API credential")
        XCTAssertFalse(encryptedDisplayTitle.contains("API credential"))
        XCTAssertEqual(security.decrypt(encryptedDisplayTitle, context: .itemDisplayTitle(itemID: item.id)), "API credential")

        let didClearTitle = await manager.updateDisplayTitle(for: item.id, displayTitle: "   ")
        XCTAssertTrue(didClearTitle)
        fetched = await manager.fetchAll()
        XCTAssertNil(fetched.first?.displayTitle)
        XCTAssertNil(try XCTUnwrap(db.pluck(items.filter(id == item.id)))[displayTitle])
    }

    func testNewDatabaseSetsCurrentSchemaVersion() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()
        let db = try Connection(databaseURL.path)

        XCTAssertEqual(try userVersion(in: db), SchemaMigrator.currentSchemaVersion)
    }

    func testNewDatabaseCreatesQueryPathIndexes() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()
        let db = try Connection(databaseURL.path)

        try assertQueryPathIndexes(in: db)
    }

    func testVersionTenDatabaseMigratesQueryPathIndexes() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        try createSchemaVersionTenTables(in: db)
        try db.run("PRAGMA user_version = 10")

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()

        XCTAssertEqual(try userVersion(in: db), SchemaMigrator.currentSchemaVersion)
        try assertQueryPathIndexes(in: db)
    }

    func testVersionElevenDatabaseBackfillsDuplicateDigests() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        try createSchemaVersionElevenTables(in: db)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let usageCount = Expression<Int>("usage_count")
        let lastUsedAt = Expression<Date?>("last_used_at")
        let captureCount = Expression<Int>("capture_count")
        let lastCapturedAt = Expression<Date?>("last_captured_at")
        let primaryContentType = Expression<String>("primary_content_type")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let duplicateDigest = Expression<String?>("duplicate_digest")
        let itemID = UUID()
        let legacyContent = "legacy duplicate"
        let encrypted = try XCTUnwrap(security.encrypt(legacyContent, context: .itemContent(itemID: itemID)))

        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- Date(timeIntervalSince1970: 1),
            bundleID <- Optional("com.example.source"),
            isSecret <- false,
            isFavorite <- false,
            usageCount <- 0,
            lastUsedAt <- nil,
            captureCount <- 1,
            lastCapturedAt <- Optional(Date(timeIntervalSince1970: 1)),
            primaryContentType <- ClipboardContentType.plainText.rawValue,
            migratedFromLegacy <- false
        ))
        try db.run("PRAGMA user_version = 11")

        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
        )
        _ = await manager.diagnosticsSnapshot()

        XCTAssertEqual(try userVersion(in: db), SchemaMigrator.currentSchemaVersion)
        let duplicateDigestColumnCount = try integerScalar(
            "SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'duplicate_digest'",
            in: db
        )
        XCTAssertEqual(duplicateDigestColumnCount, 1)
        let migratedRow = try XCTUnwrap(db.pluck(items.filter(id == itemID)))
        let storedDuplicateDigest = try XCTUnwrap(migratedRow[duplicateDigest])
        XCTAssertEqual(storedDuplicateDigest, security.duplicateContentDigest(for: legacyContent))
        XCTAssertFalse(storedDuplicateDigest.contains(legacyContent))
        try assertQueryPathIndexes(in: db)
    }

    func testUnreadableDuplicateDigestBackfillDoesNotAdvanceUserVersion() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        try createSchemaVersionElevenTables(in: db)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let usageCount = Expression<Int>("usage_count")
        let lastUsedAt = Expression<Date?>("last_used_at")
        let captureCount = Expression<Int>("capture_count")
        let lastCapturedAt = Expression<Date?>("last_captured_at")
        let primaryContentType = Expression<String>("primary_content_type")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")

        try db.run(items.insert(
            id <- UUID(),
            content <- "not encrypted content",
            timestamp <- Date(),
            bundleID <- Optional("com.example.source"),
            isSecret <- false,
            isFavorite <- false,
            usageCount <- 0,
            lastUsedAt <- nil,
            captureCount <- 1,
            lastCapturedAt <- Optional(Date()),
            primaryContentType <- ClipboardContentType.plainText.rawValue,
            migratedFromLegacy <- false
        ))
        try db.run("PRAGMA user_version = 11")

        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
        )
        _ = await manager.diagnosticsSnapshot()

        let databaseStatus = await manager.databaseStatus
        XCTAssertEqual(databaseStatus, .failed)
        XCTAssertEqual(try userVersion(in: db), 11)
        let duplicateDigestColumnCount = try integerScalar(
            "SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'duplicate_digest'",
            in: db
        )
        XCTAssertEqual(duplicateDigestColumnCount, 0)
        await assertDatabaseUnavailableAfterSetupFailure(manager)
    }

    func testDatabaseConnectionAppliesWALAndBusyTimeoutPragmas() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)

        let pragmas = try await manager.connectionPragmas()

        XCTAssertEqual(pragmas.journalMode.lowercased(), "wal")
        XCTAssertEqual(pragmas.busyTimeoutMilliseconds, 5_000)
    }

    func testFutureSchemaVersionIsRejectedWithoutDowngrade() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let futureVersion = SchemaMigrator.currentSchemaVersion + 1
        try db.run("PRAGMA user_version = \(futureVersion)")

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()

        let databaseStatus = await manager.databaseStatus
        XCTAssertEqual(databaseStatus, .failed)
        XCTAssertEqual(try userVersion(in: db), futureVersion)
        await assertDatabaseUnavailableAfterSetupFailure(manager)
    }

    func testUnreadableLegacyItemMigrationDoesNotAdvanceUserVersion() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(items.insert(
            id <- UUID(),
            content <- "not-valid-ciphertext",
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            migratedFromLegacy <- false
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()

        let databaseStatus = await manager.databaseStatus
        XCTAssertEqual(databaseStatus, .failed)
        XCTAssertEqual(try userVersion(in: db), 0)
        await assertDatabaseUnavailableAfterSetupFailure(manager)
    }

    func testUnreadableLegacyPayloadRewriteDoesNotAdvanceUserVersion() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let payloads = Table("clipboard_payloads")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadContentType = Expression<String>("content_type")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let payloadByteSize = Expression<Int>("byte_size")
        let payloadPreview = Expression<String?>("preview")
        let payloadRank = Expression<Int>("rank")
        let itemID = UUID()
        let encrypted = try XCTUnwrap(security.encrypt("legacy payload"))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(payloads.create { t in
            t.column(payloadID, primaryKey: true)
            t.column(payloadItemID)
            t.column(payloadContentType)
            t.column(payloadEncryptedData)
            t.column(payloadByteSize, defaultValue: 0)
            t.column(payloadPreview)
            t.column(payloadRank, defaultValue: 0)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            migratedFromLegacy <- false
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.plainText.rawValue,
            payloadEncryptedData <- "not-valid-ciphertext",
            payloadByteSize <- 0,
            payloadPreview <- nil,
            payloadRank <- 0
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()

        let databaseStatus = await manager.databaseStatus
        XCTAssertEqual(databaseStatus, .failed)
        XCTAssertEqual(try userVersion(in: db), 0)
        await assertDatabaseUnavailableAfterSetupFailure(manager)
    }

    func testSchema12ReencryptsLegacyDisplayTitleAndPayloadRows() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        try createSchemaVersionElevenTables(in: db)

        let items = Table("clipboard_items")
        let itemIDColumn = Expression<UUID>("id")
        let content = Expression<String>("content")
        let displayTitle = Expression<String?>("display_title")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let usageCount = Expression<Int>("usage_count")
        let lastUsedAt = Expression<Date?>("last_used_at")
        let captureCount = Expression<Int>("capture_count")
        let lastCapturedAt = Expression<Date?>("last_captured_at")
        let primaryContentType = Expression<String>("primary_content_type")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let payloads = Table("clipboard_payloads")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadContentType = Expression<String>("content_type")
        let payloadPasteboardType = Expression<String>("pasteboard_type")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let payloadByteSize = Expression<Int>("byte_size")
        let payloadPreview = Expression<String?>("preview")
        let payloadRank = Expression<Int>("rank")
        let itemID = UUID()
        let legacyPayloadID = UUID()
        let itemTimestamp = Date(timeIntervalSince1970: 1)
        let legacyContent = try XCTUnwrap(security.encrypt("legacy content"))
        let legacyTitle = try XCTUnwrap(security.encrypt("legacy title"))
        let legacyPayload = try XCTUnwrap(security.encrypt(Data("legacy payload".utf8).base64EncodedString()))

        try db.run(items.insert(
            itemIDColumn <- itemID,
            content <- legacyContent,
            displayTitle <- legacyTitle,
            timestamp <- itemTimestamp,
            bundleID <- Optional("com.example.source"),
            isSecret <- false,
            isFavorite <- false,
            usageCount <- 0,
            lastUsedAt <- nil,
            captureCount <- 1,
            lastCapturedAt <- Optional(itemTimestamp),
            primaryContentType <- ClipboardContentType.plainText.rawValue,
            migratedFromLegacy <- false
        ))
        try db.run(payloads.insert(
            payloadID <- legacyPayloadID,
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.plainText.rawValue,
            payloadPasteboardType <- NSPasteboard.PasteboardType.string.rawValue,
            payloadEncryptedData <- legacyPayload,
            payloadByteSize <- 0,
            payloadPreview <- nil,
            payloadRank <- 0
        ))
        try db.run("PRAGMA user_version = 11")

        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
        )
        let fetchedItems = await manager.fetchAll()
        let fetchedPayloads = await manager.payloads(for: itemID)
        let fetchedItem = try XCTUnwrap(fetchedItems.first)
        let fetchedPayload = try XCTUnwrap(fetchedPayloads.first)

        XCTAssertEqual(fetchedItem.content, "legacy content")
        XCTAssertEqual(fetchedItem.displayTitle, "legacy title")
        XCTAssertEqual(fetchedPayload.data, Data("legacy payload".utf8))

        let migratedItemRow = try XCTUnwrap(db.pluck(items.filter(itemIDColumn == itemID)))
        let migratedPayloadRow = try XCTUnwrap(db.pluck(payloads.filter(payloadID == legacyPayloadID)))
        XCTAssertTrue(migratedItemRow[content].hasPrefix("forkclip-aad-v1:"))
        XCTAssertTrue(migratedItemRow[displayTitle]?.hasPrefix("forkclip-aad-v1:") == true)
        XCTAssertTrue(migratedPayloadRow[payloadEncryptedData].hasPrefix("forkclip-aad-v1:"))
        XCTAssertEqual(
            security.decrypt(migratedItemRow[content], context: .itemContent(itemID: itemID)),
            "legacy content"
        )
        XCTAssertEqual(
            security.decrypt(migratedItemRow[displayTitle]!, context: .itemDisplayTitle(itemID: itemID)),
            "legacy title"
        )
        XCTAssertEqual(
            security.decrypt(
                migratedPayloadRow[payloadEncryptedData],
                context: .payloadData(itemID: itemID, payloadID: legacyPayloadID)
            ),
            Data("legacy payload".utf8).base64EncodedString()
        )
    }

    func testDatabaseFileUsesOwnerOnlyPermissions() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        _ = await manager.diagnosticsSnapshot()

        XCTAssertEqual(try posixPermissions(at: databaseURL), AppPaths.ownerOnlyFilePermissions)
    }

    func testRecoveryBackupFilePermissionPolicyUsesOwnerOnlyPermissions() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let backupURL = tempDirectory.appendingPathComponent("forkclip-recovery-test.sqlite")
        _ = FileManager.default.createFile(atPath: backupURL.path, contents: Data("backup".utf8), attributes: [
            .posixPermissions: NSNumber(value: 0o644)
        ])

        try AppPaths.applyOwnerOnlyFilePermissions(to: backupURL)

        XCTAssertEqual(try posixPermissions(at: backupURL), AppPaths.ownerOnlyFilePermissions)
    }

    func testSaveItemCreatesEncryptedMultiformatPayloadRows() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(
            id: UUID(),
            content: "rich preview",
            timestamp: Date(),
            bundleID: "com.example.source",
            primaryContentType: .html
        )
        let htmlData = Data("<p>rich</p>".utf8)
        let rtfData = Data("{\\rtf1 rich}".utf8)

        try await manager.saveItem(
            item,
            payloads: [
                ClipboardPayload(contentType: .html, pasteboardType: .html, data: htmlData, preview: "HTML", rank: 0),
                ClipboardPayload(contentType: .rtf, pasteboardType: .rtf, data: rtfData, preview: "リッチテキスト", rank: 1)
            ],
            originBundleID: item.bundleID,
            secret: false,
            migrated: false
        )

        let fetched = await manager.fetchAll()
        XCTAssertEqual(fetched.first?.content, "rich preview")
        XCTAssertEqual(fetched.first?.primaryContentType, .html)

        let fetchedPayloads = await manager.payloads(for: item.id)
        XCTAssertEqual(fetchedPayloads.map(\.contentType), [.html, .rtf])
        XCTAssertEqual(fetchedPayloads.map(\.pasteboardType), [.html, .rtf])
        XCTAssertEqual(fetchedPayloads.map(\.data), [htmlData, rtfData])
        XCTAssertEqual(fetchedPayloads.map(\.byteSize), [htmlData.count, rtfData.count])

        let db = try Connection(databaseURL.path)
        let payloadRows = Table("clipboard_payloads")
        let encryptedData = Expression<String>("encrypted_data")
        let byteSize = Expression<Int>("byte_size")
        let contentType = Expression<String>("content_type")
        let preview = Expression<String?>("preview")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let storedRows = try db.prepare(payloadRows.order(byteSize.asc)).map { $0 }

        XCTAssertEqual(storedRows.count, 2)
        XCTAssertEqual(Set(storedRows.map { $0[contentType] }), Set([ClipboardContentType.html.rawValue, ClipboardContentType.rtf.rawValue]))
        XCTAssertTrue(storedRows.allSatisfy { $0[preview] == nil })
        for row in storedRows {
            XCTAssertFalse(row[encryptedData].contains("<p>rich</p>"))
            XCTAssertFalse(row[encryptedData].contains("{\\rtf1 rich}"))
            let decrypted = try XCTUnwrap(security.decrypt(
                row[encryptedData],
                context: .payloadData(itemID: row[payloadItemID], payloadID: row[payloadID])
            ))
            XCTAssertNotNil(Data(base64Encoded: decrypted))
        }
    }

    func testSaveItemThrowsDatabaseUnavailableWhenOpenFails() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(id: UUID(), content: "unavailable", timestamp: Date())

        await assertThrowsPersistenceError {
            try await manager.saveItem(item, originBundleID: nil, secret: false, migrated: false)
        } verify: { error in
            XCTAssertEqual(error, .databaseUnavailable)
        }
    }

    func testItemCiphertextCannotBeSwappedAcrossRows() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
        )
        let firstItem = ClipboardItem(id: UUID(), content: "first bound value", timestamp: Date(timeIntervalSince1970: 1))
        let secondItem = ClipboardItem(id: UUID(), content: "second bound value", timestamp: Date(timeIntervalSince1970: 2))

        try await manager.saveItem(firstItem, originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(secondItem, originBundleID: nil, secret: false, migrated: false)

        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let firstCiphertext = try XCTUnwrap(db.pluck(items.filter(id == firstItem.id)))[content]
        let secondCiphertext = try XCTUnwrap(db.pluck(items.filter(id == secondItem.id)))[content]

        try db.run(items.filter(id == firstItem.id).update(content <- secondCiphertext))
        try db.run(items.filter(id == secondItem.id).update(content <- firstCiphertext))

        let fetchedAfterSwap = await manager.fetchAll()
        let lastFetchFailureCount = await manager.lastFetchFailureCount
        XCTAssertTrue(fetchedAfterSwap.isEmpty)
        XCTAssertEqual(lastFetchFailureCount, 2)
    }

    func testPayloadCiphertextCannotBeSwappedAcrossRows() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(
            id: UUID(),
            content: "payload swap",
            timestamp: Date(),
            primaryContentType: .html
        )
        let firstPayload = ClipboardPayload(
            id: UUID(),
            contentType: .plainText,
            pasteboardType: .string,
            data: Data("plain".utf8),
            rank: 0
        )
        let secondPayload = ClipboardPayload(
            id: UUID(),
            contentType: .html,
            pasteboardType: .html,
            data: Data("<p>html</p>".utf8),
            rank: 1
        )

        try await manager.saveItem(
            item,
            payloads: [firstPayload, secondPayload],
            originBundleID: nil,
            secret: false,
            migrated: false
        )

        let db = try Connection(databaseURL.path)
        let payloads = Table("clipboard_payloads")
        let payloadID = Expression<UUID>("id")
        let encryptedData = Expression<String>("encrypted_data")
        let firstCiphertext = try XCTUnwrap(db.pluck(payloads.filter(payloadID == firstPayload.id)))[encryptedData]
        let secondCiphertext = try XCTUnwrap(db.pluck(payloads.filter(payloadID == secondPayload.id)))[encryptedData]

        try db.run(payloads.filter(payloadID == firstPayload.id).update(encryptedData <- secondCiphertext))
        try db.run(payloads.filter(payloadID == secondPayload.id).update(encryptedData <- firstCiphertext))

        let fetchedPayloadsAfterSwap = await manager.payloads(for: item.id)
        XCTAssertTrue(fetchedPayloadsAfterSwap.isEmpty)
    }

    func testSaveItemDistinguishesItemRowAndPayloadRowFailures() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let duplicateItem = ClipboardItem(id: UUID(), content: "duplicate item", timestamp: Date())

        try await manager.saveItem(duplicateItem, originBundleID: nil, secret: false, migrated: false)
        await assertThrowsPersistenceError {
            try await manager.saveItem(duplicateItem, originBundleID: nil, secret: false, migrated: false)
        } verify: { error in
            guard case .itemWriteFailed = error else {
                return XCTFail("Expected itemWriteFailed, got \(error)")
            }
        }

        let payloadID = UUID()
        let payloadItem = ClipboardItem(id: UUID(), content: "duplicate payload", timestamp: Date())
        let payloads = [
            ClipboardPayload(id: payloadID, contentType: .plainText, pasteboardType: .string, data: Data("first".utf8), rank: 0),
            ClipboardPayload(id: payloadID, contentType: .html, pasteboardType: .html, data: Data("<p>second</p>".utf8), rank: 1)
        ]

        await assertThrowsPersistenceError {
            try await manager.saveItem(payloadItem, payloads: payloads, originBundleID: nil, secret: false, migrated: false)
        } verify: { error in
            guard case .payloadWriteFailed(let contentType, let pasteboardType, _) = error else {
                return XCTFail("Expected payloadWriteFailed, got \(error)")
            }
            XCTAssertEqual(contentType, .html)
            XCTAssertEqual(pasteboardType, NSPasteboard.PasteboardType.html.rawValue)
        }
        let fetchedAfterFailedPayloadSave = await manager.fetchAll()
        XCTAssertFalse(fetchedAfterFailedPayloadSave.contains { $0.id == payloadItem.id })
    }

    func testRetentionPolicyPrunesOldestStoredItems() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: 2)
        )

        try await manager.saveItem(ClipboardItem(id: UUID(), content: "first", timestamp: Date(timeIntervalSince1970: 1)), originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "second", timestamp: Date(timeIntervalSince1970: 2)), originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "third", timestamp: Date(timeIntervalSince1970: 3)), originBundleID: nil, secret: false, migrated: false)

        let fetched = await manager.fetchAll()
        XCTAssertEqual(fetched.map(\.content), ["third", "second"])

        let db = try Connection(databaseURL.path)
        XCTAssertEqual(try db.scalar(Table("clipboard_items").count), 2)
        XCTAssertEqual(try db.scalar(Table("clipboard_payloads").count), 2)
    }

    func testFavoriteStatePersistsAcrossDatabaseManagers() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let item = ClipboardItem(id: UUID(), content: "favorite", timestamp: Date())

        do {
            let manager = makeDatabaseManager(databaseURL: databaseURL)
            try await manager.saveItem(item, originBundleID: nil, secret: false, migrated: false)
            let didUpdateFavorite = await manager.updateFavoriteState(for: item.id, isFavorite: true)
            XCTAssertTrue(didUpdateFavorite)
        }

        let reopenedManager = makeDatabaseManager(databaseURL: databaseURL)
        let fetched = await reopenedManager.fetchAll()

        XCTAssertEqual(fetched.map(\.content), ["favorite"])
        XCTAssertEqual(fetched.first?.isFavorite, true)
    }

    func testUsageCountPersistsAcrossDatabaseManagers() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let retentionPolicy = ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
        let manager = makeDatabaseManager(databaseURL: databaseURL, retentionPolicy: retentionPolicy)
        let item = ClipboardItem(id: UUID(), content: "reused", timestamp: Date(timeIntervalSince1970: 1))
        let firstUse = Date(timeIntervalSince1970: 10)
        let secondUse = Date(timeIntervalSince1970: 20)

        try await manager.saveItem(item, originBundleID: nil, secret: false, migrated: false)

        let firstRecordedUse = await manager.recordUse(for: item.id, at: firstUse)
        let firstUpdate = try XCTUnwrap(firstRecordedUse)
        XCTAssertEqual(firstUpdate.usageCount, 1)
        XCTAssertEqual(try XCTUnwrap(firstUpdate.lastUsedAt).timeIntervalSince1970, firstUse.timeIntervalSince1970, accuracy: 0.001)

        let secondRecordedUse = await manager.recordUse(for: item.id, at: secondUse)
        let secondUpdate = try XCTUnwrap(secondRecordedUse)
        XCTAssertEqual(secondUpdate.usageCount, 2)
        XCTAssertEqual(try XCTUnwrap(secondUpdate.lastUsedAt).timeIntervalSince1970, secondUse.timeIntervalSince1970, accuracy: 0.001)

        let reloadedManager = makeDatabaseManager(databaseURL: databaseURL, retentionPolicy: retentionPolicy)
        let reloadedItems = await reloadedManager.fetchAll()
        let fetched = try XCTUnwrap(reloadedItems.first)
        XCTAssertEqual(fetched.usageCount, 2)
        XCTAssertEqual(try XCTUnwrap(fetched.lastUsedAt).timeIntervalSince1970, secondUse.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(fetched.captureCount, 1)
    }

    func testDuplicateCaptureCountPersistsAcrossDatabaseManagers() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let now = Date()
        let original = ClipboardItem(
            id: UUID(),
            content: "repeat me",
            timestamp: now.addingTimeInterval(-20),
            bundleID: "com.example.source"
        )
        let other = ClipboardItem(
            id: UUID(),
            content: "newer once",
            timestamp: now.addingTimeInterval(-10),
            bundleID: "com.example.source"
        )
        let duplicateDate = now

        try await manager.saveItem(original, originBundleID: original.bundleID, secret: false, migrated: false)
        try await manager.saveItem(other, originBundleID: other.bundleID, secret: false, migrated: false)
        let savedItems = await manager.fetchAll()
        XCTAssertEqual(savedItems.map(\.content), ["newer once", "repeat me"])

        let recordedDuplicate = await manager.recordDuplicateCapture(
            content: "repeat me",
            primaryContentType: .plainText,
            bundleID: "com.example.source",
            at: duplicateDate
        )

        let updated = try XCTUnwrap(recordedDuplicate)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.captureCount, 2)
        XCTAssertEqual(updated.lastCapturedAt.timeIntervalSince1970, duplicateDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(updated.usageCount, 0)

        let reloadedManager = makeDatabaseManager(databaseURL: databaseURL)
        let reloadedItems = await reloadedManager.fetchAll()

        XCTAssertEqual(reloadedItems.map(\.content), ["repeat me", "newer once"])
        XCTAssertEqual(reloadedItems.first?.captureCount, 2)
        XCTAssertEqual(try XCTUnwrap(reloadedItems.first?.lastCapturedAt).timeIntervalSince1970, duplicateDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(reloadedItems.first?.usageCount, 0)
    }

    func testDuplicateLookupUsesDigestWithoutDecryptingNonMatchingCandidates() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let countingSecurity = CountingClipboardCryptography()
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil),
            security: countingSecurity
        )
        let now = Date()
        let original = ClipboardItem(
            id: UUID(),
            content: "repeat me",
            timestamp: now.addingTimeInterval(-20),
            bundleID: "com.example.source"
        )
        let newerNonMatch = ClipboardItem(
            id: UUID(),
            content: "newer once",
            timestamp: now.addingTimeInterval(-10),
            bundleID: "com.example.source"
        )

        try await manager.saveItem(original, originBundleID: original.bundleID, secret: false, migrated: false)
        try await manager.saveItem(newerNonMatch, originBundleID: newerNonMatch.bundleID, secret: false, migrated: false)
        countingSecurity.resetCounters()

        let recordedDuplicate = await manager.recordDuplicateCapture(
            content: "repeat me",
            primaryContentType: .plainText,
            bundleID: "com.example.source",
            at: now
        )

        let updated = try XCTUnwrap(recordedDuplicate)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(countingSecurity.decryptCallCount, 1)
    }

    func testDuplicateLookupDoesNotMatchDifferentSourceOrPrimaryType() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
        )
        let item = ClipboardItem(
            id: UUID(),
            content: "shared value",
            timestamp: Date(timeIntervalSince1970: 1),
            bundleID: "com.example.source",
            primaryContentType: .plainText
        )

        try await manager.saveItem(item, originBundleID: item.bundleID, secret: false, migrated: false)

        let differentSource = await manager.recordDuplicateCapture(
            content: "shared value",
            primaryContentType: .plainText,
            bundleID: "com.example.other",
            at: Date(timeIntervalSince1970: 2)
        )
        let differentPrimaryType = await manager.recordDuplicateCapture(
            content: "shared value",
            primaryContentType: .html,
            bundleID: "com.example.source",
            at: Date(timeIntervalSince1970: 3)
        )
        let fetched = await manager.fetchAll()

        XCTAssertNil(differentSource)
        XCTAssertNil(differentPrimaryType)
        XCTAssertEqual(fetched.first?.captureCount, 1)
        XCTAssertEqual(try XCTUnwrap(fetched.first?.lastCapturedAt).timeIntervalSince1970, item.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testUpdateFavoriteStateReturnsFalseForMissingItem() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)

        let didUpdateFavorite = await manager.updateFavoriteState(for: UUID(), isFavorite: true)
        XCTAssertFalse(didUpdateFavorite)
    }

    func testExistingDatabaseMigratesFavoriteColumnWithDefaultFalse() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let displayTitle = Expression<String?>("display_title")
        let captureCount = Expression<Int>("capture_count")
        let lastCapturedAt = Expression<Date?>("last_captured_at")
        let itemID = UUID()
        let createdAt = Date()
        let encrypted = try XCTUnwrap(security.encrypt("legacy favorite default"))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- createdAt,
            bundleID <- nil,
            isSecret <- false,
            migratedFromLegacy <- false
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetched = await manager.fetchAll()
        let favoriteColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'is_favorite'") as? Int64 ?? 0
        let usageCountColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'usage_count'") as? Int64 ?? 0
        let lastUsedAtColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'last_used_at'") as? Int64 ?? 0
        let captureCountColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'capture_count'") as? Int64 ?? 0
        let lastCapturedAtColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'last_captured_at'") as? Int64 ?? 0
        let displayTitleColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'display_title'") as? Int64 ?? 0
        let itemRow = try XCTUnwrap(db.pluck(items))

        XCTAssertEqual(favoriteColumnCount, 1)
        XCTAssertEqual(usageCountColumnCount, 1)
        XCTAssertEqual(lastUsedAtColumnCount, 1)
        XCTAssertEqual(captureCountColumnCount, 1)
        XCTAssertEqual(lastCapturedAtColumnCount, 1)
        XCTAssertEqual(displayTitleColumnCount, 1)
        XCTAssertEqual(try userVersion(in: db), SchemaMigrator.currentSchemaVersion)
        XCTAssertEqual(fetched.first?.content, "legacy favorite default")
        XCTAssertNil(fetched.first?.displayTitle)
        XCTAssertEqual(fetched.first?.isFavorite, false)
        XCTAssertEqual(fetched.first?.usageCount, 0)
        XCTAssertNil(fetched.first?.lastUsedAt)
        XCTAssertEqual(itemRow[captureCount], 1)
        XCTAssertNil(itemRow[displayTitle])
        XCTAssertEqual(try XCTUnwrap(itemRow[lastCapturedAt]).timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(fetched.first?.captureCount, 1)
        XCTAssertEqual(try XCTUnwrap(fetched.first?.lastCapturedAt).timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testExistingDatabaseMigratesPrimaryContentTypeColumnWithDefaultPlainText() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let itemID = UUID()
        let encrypted = try XCTUnwrap(security.encrypt("legacy primary type default"))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(isFavorite, defaultValue: false)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            isFavorite <- false,
            migratedFromLegacy <- false
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetched = await manager.fetchAll()
        let primaryTypeColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'primary_content_type'") as? Int64 ?? 0

        XCTAssertEqual(primaryTypeColumnCount, 1)
        XCTAssertEqual(fetched.first?.content, "legacy primary type default")
        XCTAssertEqual(fetched.first?.primaryContentType, .plainText)
    }

    func testLegacyItemWithoutPayloadMigratesBase64LikeTextToPayloadBytes() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let itemID = UUID()
        let legacyText = "test"
        let encrypted = try XCTUnwrap(security.encrypt(legacyText))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            migratedFromLegacy <- false
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetchedPayloads = await manager.payloads(for: itemID)

        XCTAssertEqual(fetchedPayloads.first?.contentType, .plainText)
        XCTAssertEqual(fetchedPayloads.first?.pasteboardType, .string)
        XCTAssertEqual(fetchedPayloads.first?.data, Data(legacyText.utf8))
        XCTAssertEqual(fetchedPayloads.first?.byteSize, legacyText.utf8.count)

        let payloads = Table("clipboard_payloads")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let row = try XCTUnwrap(db.pluck(payloads))
        let decryptedPayload = try XCTUnwrap(security.decrypt(
            row[payloadEncryptedData],
            context: .payloadData(itemID: row[payloadItemID], payloadID: row[payloadID])
        ))
        XCTAssertEqual(Data(base64Encoded: decryptedPayload), Data(legacyText.utf8))
        XCTAssertNotEqual(decryptedPayload, legacyText)
    }

    func testExistingPlainTextPayloadMigratesBase64LikeRawTextEncoding() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let payloads = Table("clipboard_payloads")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadContentType = Expression<String>("content_type")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let payloadByteSize = Expression<Int>("byte_size")
        let payloadPreview = Expression<String?>("preview")
        let payloadRank = Expression<Int>("rank")
        let itemID = UUID()
        let legacyText = "test"
        let encrypted = try XCTUnwrap(security.encrypt(legacyText))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(payloads.create { t in
            t.column(payloadID, primaryKey: true)
            t.column(payloadItemID)
            t.column(payloadContentType)
            t.column(payloadEncryptedData)
            t.column(payloadByteSize, defaultValue: 0)
            t.column(payloadPreview)
            t.column(payloadRank, defaultValue: 0)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            migratedFromLegacy <- false
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.plainText.rawValue,
            payloadEncryptedData <- encrypted,
            payloadByteSize <- 0,
            payloadPreview <- nil,
            payloadRank <- 0
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetchedPayloads = await manager.payloads(for: itemID)

        XCTAssertEqual(fetchedPayloads.first?.contentType, .plainText)
        XCTAssertEqual(fetchedPayloads.first?.pasteboardType, .string)
        XCTAssertEqual(fetchedPayloads.first?.data, Data(legacyText.utf8))
        XCTAssertEqual(fetchedPayloads.first?.byteSize, legacyText.utf8.count)

        let row = try XCTUnwrap(db.pluck(payloads))
        let decryptedPayload = try XCTUnwrap(security.decrypt(
            row[payloadEncryptedData],
            context: .payloadData(itemID: row[payloadItemID], payloadID: row[payloadID])
        ))
        XCTAssertEqual(Data(base64Encoded: decryptedPayload), Data(legacyText.utf8))
        XCTAssertNotEqual(decryptedPayload, legacyText)
    }

    func testExistingDatabaseBackfillsPrimaryContentTypeFromRankedPayloads() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let payloads = Table("clipboard_payloads")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadContentType = Expression<String>("content_type")
        let payloadPasteboardType = Expression<String>("pasteboard_type")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let payloadByteSize = Expression<Int>("byte_size")
        let payloadPreview = Expression<String?>("preview")
        let payloadRank = Expression<Int>("rank")
        let itemID = UUID()
        let encryptedContent = try XCTUnwrap(security.encrypt("画像"))
        let encryptedImage = try XCTUnwrap(security.encrypt(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()))
        let encryptedText = try XCTUnwrap(security.encrypt(Data("fallback".utf8).base64EncodedString()))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(isFavorite, defaultValue: false)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(payloads.create { t in
            t.column(payloadID, primaryKey: true)
            t.column(payloadItemID)
            t.column(payloadContentType)
            t.column(payloadPasteboardType, defaultValue: NSPasteboard.PasteboardType.string.rawValue)
            t.column(payloadEncryptedData)
            t.column(payloadByteSize, defaultValue: 0)
            t.column(payloadPreview)
            t.column(payloadRank, defaultValue: 0)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encryptedContent,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            isFavorite <- false,
            migratedFromLegacy <- false
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.image.rawValue,
            payloadPasteboardType <- NSPasteboard.PasteboardType.png.rawValue,
            payloadEncryptedData <- encryptedImage,
            payloadByteSize <- 4,
            payloadPreview <- "画像",
            payloadRank <- 0
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.plainText.rawValue,
            payloadPasteboardType <- NSPasteboard.PasteboardType.string.rawValue,
            payloadEncryptedData <- encryptedText,
            payloadByteSize <- "fallback".utf8.count,
            payloadPreview <- nil,
            payloadRank <- 1
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetched = await manager.fetchAll()
        let fetchedPayloads = await manager.payloads(for: itemID)

        XCTAssertEqual(fetched.first?.content, "画像")
        XCTAssertEqual(fetched.first?.primaryContentType, .image)
        XCTAssertTrue(fetchedPayloads.allSatisfy { $0.preview == nil })
    }

    func testExistingFileURLPrimaryTypeBackfillsToImageWhenImagePayloadExists() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let payloads = Table("clipboard_payloads")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let primaryContentType = Expression<String>("primary_content_type")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadContentType = Expression<String>("content_type")
        let payloadPasteboardType = Expression<String>("pasteboard_type")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let payloadByteSize = Expression<Int>("byte_size")
        let payloadPreview = Expression<String?>("preview")
        let payloadRank = Expression<Int>("rank")
        let itemID = UUID()
        let encryptedContent = try XCTUnwrap(security.encrypt("ファイル: cleanshot.png"))
        let encryptedFileURL = try XCTUnwrap(security.encrypt(Data("file:///Users/example/Desktop/cleanshot.png".utf8).base64EncodedString()))
        let encryptedImage = try XCTUnwrap(security.encrypt(Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(isFavorite, defaultValue: false)
            t.column(primaryContentType, defaultValue: ClipboardContentType.plainText.rawValue)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(payloads.create { t in
            t.column(payloadID, primaryKey: true)
            t.column(payloadItemID)
            t.column(payloadContentType)
            t.column(payloadPasteboardType, defaultValue: NSPasteboard.PasteboardType.string.rawValue)
            t.column(payloadEncryptedData)
            t.column(payloadByteSize, defaultValue: 0)
            t.column(payloadPreview)
            t.column(payloadRank, defaultValue: 0)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encryptedContent,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            isFavorite <- false,
            primaryContentType <- ClipboardContentType.fileURL.rawValue,
            migratedFromLegacy <- false
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.fileURL.rawValue,
            payloadPasteboardType <- NSPasteboard.PasteboardType.fileURL.rawValue,
            payloadEncryptedData <- encryptedFileURL,
            payloadByteSize <- "file:///Users/example/Desktop/cleanshot.png".utf8.count,
            payloadPreview <- "ファイル: cleanshot.png",
            payloadRank <- 0
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.image.rawValue,
            payloadPasteboardType <- NSPasteboard.PasteboardType.png.rawValue,
            payloadEncryptedData <- encryptedImage,
            payloadByteSize <- 4,
            payloadPreview <- "画像",
            payloadRank <- 1
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetched = await manager.fetchAll()
        let fetchedPayloads = await manager.payloads(for: itemID)

        XCTAssertEqual(fetched.first?.content, "ファイル: cleanshot.png")
        XCTAssertEqual(fetched.first?.primaryContentType, .image)
        XCTAssertEqual(fetchedPayloads.map(\.contentType), [.fileURL, .image])
        XCTAssertEqual(fetchedPayloads.map(\.rank), [0, 1])
        XCTAssertEqual(fetchedPayloads.map(\.data), [
            Data("file:///Users/example/Desktop/cleanshot.png".utf8),
            Data([0x89, 0x50, 0x4E, 0x47])
        ])
        XCTAssertTrue(fetchedPayloads.allSatisfy { $0.preview == nil })
    }

    func testExistingPayloadTableMigratesPasteboardTypeColumn() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let db = try Connection(databaseURL.path)
        let items = Table("clipboard_items")
        let payloads = Table("clipboard_payloads")
        let id = Expression<UUID>("id")
        let content = Expression<String>("content")
        let timestamp = Expression<Date>("timestamp")
        let bundleID = Expression<String?>("bundle_id")
        let isSecret = Expression<Bool>("is_secret")
        let isFavorite = Expression<Bool>("is_favorite")
        let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")
        let payloadID = Expression<UUID>("id")
        let payloadItemID = Expression<UUID>("item_id")
        let payloadContentType = Expression<String>("content_type")
        let payloadEncryptedData = Expression<String>("encrypted_data")
        let payloadByteSize = Expression<Int>("byte_size")
        let payloadPreview = Expression<String?>("preview")
        let payloadRank = Expression<Int>("rank")
        let itemID = UUID()
        let encrypted = try XCTUnwrap(security.encrypt("legacy payload"))

        try db.run(items.create { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(isFavorite, defaultValue: false)
            t.column(migratedFromLegacy, defaultValue: false)
        })
        try db.run(payloads.create { t in
            t.column(payloadID, primaryKey: true)
            t.column(payloadItemID)
            t.column(payloadContentType)
            t.column(payloadEncryptedData)
            t.column(payloadByteSize, defaultValue: 0)
            t.column(payloadPreview)
            t.column(payloadRank, defaultValue: 0)
        })
        try db.run(items.insert(
            id <- itemID,
            content <- encrypted,
            timestamp <- Date(),
            bundleID <- nil,
            isSecret <- false,
            isFavorite <- false,
            migratedFromLegacy <- false
        ))
        try db.run(payloads.insert(
            payloadID <- UUID(),
            payloadItemID <- itemID,
            payloadContentType <- ClipboardContentType.plainText.rawValue,
            payloadEncryptedData <- encrypted,
            payloadByteSize <- 0,
            payloadPreview <- nil,
            payloadRank <- 0
        ))

        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let fetchedPayloads = await manager.payloads(for: itemID)
        let pasteboardTypeColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_payloads') WHERE name = 'pasteboard_type'") as? Int64 ?? 0

        XCTAssertEqual(pasteboardTypeColumnCount, 1)
        XCTAssertEqual(fetchedPayloads.first?.contentType, .plainText)
        XCTAssertEqual(fetchedPayloads.first?.pasteboardType, .string)
        XCTAssertEqual(fetchedPayloads.first?.data, Data("legacy payload".utf8))
    }

    func testMissingRetentionPolicyDoesNotPruneExistingDatabaseOnOpen() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let missingPolicyURL = tempDirectory.appendingPathComponent("missing_retention_policy.json")

        do {
            let seedManager = makeDatabaseManager(
                databaseURL: databaseURL,
                retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 200)
            )

            for index in 0..<105 {
                try await seedManager.saveItem(
                    ClipboardItem(
                        id: UUID(),
                        content: "old item \(index)",
                        timestamp: Date().addingTimeInterval(-172_800 - Double(index))
                    ),
                    originBundleID: nil,
                    secret: false,
                    migrated: false
                )
            }
        }

        let reopenedManager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy.load(from: missingPolicyURL)
        )
        let fetched = await reopenedManager.fetchAll()
        let db = try Connection(databaseURL.path)

        XCTAssertEqual(fetched.count, AppSettings.defaultFetchLimit)
        XCTAssertEqual(try db.scalar(Table("clipboard_items").count), 105)
        XCTAssertEqual(try db.scalar(Table("clipboard_payloads").count), 105)
    }

    func testFolderCRUDAndAssignments() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(id: UUID(), content: "folder me", timestamp: Date())

        try await manager.saveItem(item, originBundleID: nil, secret: false, migrated: false)
        let createdFolder = await manager.createFolder(named: "Projects")
        let folder = try XCTUnwrap(createdFolder)
        let foldersAfterCreate = await manager.fetchFolders()
        XCTAssertEqual(foldersAfterCreate.map(\.name), ["Projects"])

        let didAssign = await manager.assignItem(item.id, toFolder: folder.id)
        let assignmentsAfterAssign = await manager.fetchFolderAssignments()
        XCTAssertTrue(didAssign)
        XCTAssertEqual(assignmentsAfterAssign[item.id], [folder.id])

        var renamed = folder
        renamed.name = "Archive"
        let didRename = await manager.updateFolder(renamed)
        let foldersAfterRename = await manager.fetchFolders()
        XCTAssertTrue(didRename)
        XCTAssertEqual(foldersAfterRename.map(\.name), ["Archive"])

        await manager.unassignItem(item.id, fromFolder: folder.id)
        let assignmentsAfterUnassign = await manager.fetchFolderAssignments()
        XCTAssertTrue(assignmentsAfterUnassign[item.id]?.isEmpty ?? true)

        let didReassign = await manager.assignItem(item.id, toFolder: folder.id)
        XCTAssertTrue(didReassign)
        await manager.deleteFolder(withID: folder.id)
        let foldersAfterDelete = await manager.fetchFolders()
        let assignmentsAfterFolderDelete = await manager.fetchFolderAssignments()
        let itemsAfterFolderDelete = await manager.fetchAll()
        XCTAssertTrue(foldersAfterDelete.isEmpty)
        XCTAssertTrue(assignmentsAfterFolderDelete[item.id]?.isEmpty ?? true)
        XCTAssertEqual(itemsAfterFolderDelete.map(\.content), ["folder me"])
    }

    func testDeletingItemRemovesFolderAssignments() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let item = ClipboardItem(id: UUID(), content: "delete me", timestamp: Date())

        try await manager.saveItem(item, originBundleID: nil, secret: false, migrated: false)
        let createdFolder = await manager.createFolder(named: "Projects")
        let folder = try XCTUnwrap(createdFolder)
        let didAssign = await manager.assignItem(item.id, toFolder: folder.id)
        XCTAssertTrue(didAssign)

        await manager.deleteItem(withID: item.id)

        let fetchedAfterDelete = await manager.fetchAll()
        let assignmentsAfterDelete = await manager.fetchFolderAssignments()
        XCTAssertTrue(fetchedAfterDelete.isEmpty)
        XCTAssertTrue(assignmentsAfterDelete[item.id]?.isEmpty ?? true)
    }

    func testRetentionPolicyPrunesExpiredItems() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxAgeDays: 1)
        )

        try await manager.saveItem(ClipboardItem(id: UUID(), content: "old", timestamp: Date().addingTimeInterval(-172_800)), originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "fresh", timestamp: Date()), originBundleID: nil, secret: false, migrated: false)

        let fetched = await manager.fetchAll()
        XCTAssertEqual(fetched.map(\.content), ["fresh"])
    }

    func testRetentionPolicyDoesNotPruneFavoriteItemsByCountOrAge() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: 1, maxAgeDays: 1)
        )
        let oldFavorite = ClipboardItem(
            id: UUID(),
            content: "old favorite",
            timestamp: Date().addingTimeInterval(-172_800),
            isFavorite: true
        )

        try await manager.saveItem(oldFavorite, originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "older normal", timestamp: Date(timeIntervalSince1970: 1)), originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "new normal", timestamp: Date()), originBundleID: nil, secret: false, migrated: false)

        let fetched = await manager.fetchAll()

        XCTAssertEqual(fetched.map(\.content), ["new normal", "old favorite"])
        XCTAssertEqual(fetched.first(where: { $0.content == "old favorite" })?.isFavorite, true)
    }

    func testRetentionPolicyDecodesAndClampsUntrustedValues() throws {
        let data = Data("""
        {
          "fetchLimit": -9223372036854775808,
          "maxStoredItems": 9223372036854775807,
          "maxAgeDays": -9223372036854775808
        }
        """.utf8)

        let policy = try JSONDecoder().decode(ClipboardRetentionPolicy.self, from: data)

        XCTAssertEqual(policy.fetchLimit, 1)
        XCTAssertEqual(policy.maxStoredItems, ClipboardRetentionPolicy.maxStoredItemsLimit)
        XCTAssertEqual(policy.maxAgeDays, 1)
    }

    func testPayloadQuotaPrunesOldestNonFavoriteBeforeNewCapture() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil),
            payloadQuotaBytes: 12
        )
        let oldItem = ClipboardItem(id: UUID(), content: "old", timestamp: Date(timeIntervalSince1970: 1))
        let favoriteItem = ClipboardItem(
            id: UUID(),
            content: "favorite",
            timestamp: Date(timeIntervalSince1970: 2),
            isFavorite: true
        )
        let newItem = ClipboardItem(id: UUID(), content: "new", timestamp: Date(timeIntervalSince1970: 3))
        let payload = {
            [ClipboardPayload(
                id: UUID(),
                contentType: .plainText,
                pasteboardType: .string,
                data: Data(repeating: 0x41, count: 6),
                rank: 0
            )]
        }

        try await manager.saveItem(
            oldItem,
            payloads: payload(),
            originBundleID: nil,
            secret: false,
            migrated: false
        )
        try await manager.saveItem(
            favoriteItem,
            payloads: payload(),
            originBundleID: nil,
            secret: false,
            migrated: false
        )
        try await manager.saveItem(
            newItem,
            payloads: payload(),
            originBundleID: nil,
            secret: false,
            migrated: false
        )

        let fetched = await manager.fetchAll()
        XCTAssertEqual(Set(fetched.map(\.content)), Set(["new", "favorite"]))
        XCTAssertTrue(fetched.contains(where: { $0.id == favoriteItem.id && $0.isFavorite }))
        XCTAssertFalse(fetched.contains(where: { $0.id == oldItem.id }))
    }

    func testOverQuotaFavoriteDatabaseRemainsAvailableAndRejectsNewSaveAtomically() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let favoriteItem = ClipboardItem(
            id: UUID(),
            content: "favorite over quota",
            timestamp: Date(timeIntervalSince1970: 2),
            isFavorite: true
        )
        let oldItem = ClipboardItem(
            id: UUID(),
            content: "old nonfavorite",
            timestamp: Date(timeIntervalSince1970: 1)
        )
        let payload = { (count: Int) in
            [ClipboardPayload(
                contentType: .plainText,
                pasteboardType: .string,
                data: Data(repeating: 0x41, count: count),
                rank: 0
            )]
        }

        do {
            let retentionPolicy = ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil)
            let seedManager = makeDatabaseManager(
                databaseURL: databaseURL,
                retentionPolicy: retentionPolicy,
                payloadQuotaBytes: 100
            )
            try await seedManager.saveItem(
                oldItem,
                payloads: payload(4),
                originBundleID: nil,
                secret: false,
                migrated: false
            )
            try await seedManager.saveItem(
                favoriteItem,
                payloads: payload(12),
                originBundleID: nil,
                secret: false,
                migrated: false
            )
        }

        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 10, maxStoredItems: nil, maxAgeDays: nil),
            payloadQuotaBytes: 10
        )
        let diagnostics = await manager.diagnosticsSnapshot()
        XCTAssertEqual(diagnostics.databaseStatus, .available)
        let openedItems = await manager.fetchAll()
        XCTAssertEqual(Set(openedItems.map(\.id)), Set([oldItem.id, favoriteItem.id]))

        let newItem = ClipboardItem(id: UUID(), content: "new", timestamp: Date(timeIntervalSince1970: 3))
        await assertThrowsPersistenceError {
            try await manager.saveItem(
                newItem,
                payloads: payload(1),
                originBundleID: nil,
                secret: false,
                migrated: false
            )
        } verify: { error in
            guard case .payloadQuotaExceeded = error else {
                return XCTFail("Expected payloadQuotaExceeded, got \(error)")
            }
        }

        let afterFailedSave = await manager.fetchAll()
        XCTAssertEqual(Set(afterFailedSave.map(\.id)), Set([oldItem.id, favoriteItem.id]))
        XCTAssertTrue(afterFailedSave.contains(where: { $0.id == favoriteItem.id && $0.isFavorite }))
    }

    func testSaveItemRejectsAggregatePayloadsBeforePersistence() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(databaseURL: databaseURL)
        let payloadSize = ClipboardResourceLimits.maxCaptureBytes / 2 + 1
        let payloads = [
            ClipboardPayload(
                contentType: .image,
                pasteboardType: .png,
                data: Data(repeating: 0x41, count: payloadSize),
                rank: 0
            ),
            ClipboardPayload(
                contentType: .image,
                pasteboardType: .png,
                data: Data(repeating: 0x42, count: payloadSize),
                rank: 1
            )
        ]

        await assertThrowsPersistenceError {
            try await manager.saveItem(
                ClipboardItem(id: UUID(), content: "aggregate payloads", timestamp: Date()),
                payloads: payloads,
                originBundleID: nil,
                secret: false,
                migrated: false
            )
        } verify: { error in
            guard case .captureResourceLimitExceeded(let totalBytes, let limit) = error else {
                return XCTFail("Expected captureResourceLimitExceeded, got \(error)")
            }
            XCTAssertGreaterThan(totalBytes, limit)
            XCTAssertEqual(limit, ClipboardResourceLimits.maxCaptureBytes)
        }

        let fetched = await manager.fetchAll()
        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchAllIncludesFavoritesOutsideFetchLimit() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("forkclip-test.sqlite")
        let manager = makeDatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 1)
        )

        try await manager.saveItem(ClipboardItem(id: UUID(), content: "old favorite", timestamp: Date(timeIntervalSince1970: 1), isFavorite: true), originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "middle normal", timestamp: Date(timeIntervalSince1970: 2)), originBundleID: nil, secret: false, migrated: false)
        try await manager.saveItem(ClipboardItem(id: UUID(), content: "new normal", timestamp: Date(timeIntervalSince1970: 3)), originBundleID: nil, secret: false, migrated: false)

        let fetched = await manager.fetchAll()

        XCTAssertEqual(fetched.map(\.content), ["new normal", "old favorite"])
        XCTAssertEqual(fetched.first(where: { $0.content == "old favorite" })?.isFavorite, true)
    }

    private func userVersion(in db: Connection) throws -> Int {
        let value = try db.scalar("PRAGMA user_version")
        if let intValue = value as? Int64 {
            return Int(intValue)
        }
        if let intValue = value as? Int {
            return intValue
        }
        return 0
    }

    private struct ExpectedSchemaIndex {
        let name: String
        let table: String
        let terms: [ExpectedSchemaIndexTerm]
    }

    private struct ExpectedSchemaIndexTerm {
        let column: String
        let descending: Bool
    }

    private func expectedQueryPathIndexes() -> [ExpectedSchemaIndex] {
        [
            ExpectedSchemaIndex(
                name: "idx_clipboard_payloads_item_id_rank",
                table: "clipboard_payloads",
                terms: [
                    ExpectedSchemaIndexTerm(column: "item_id", descending: false),
                    ExpectedSchemaIndexTerm(column: "rank", descending: false)
                ]
            ),
            ExpectedSchemaIndex(
                name: "idx_clipboard_item_folders_item_id_folder_id",
                table: "clipboard_item_folders",
                terms: [
                    ExpectedSchemaIndexTerm(column: "item_id", descending: false),
                    ExpectedSchemaIndexTerm(column: "folder_id", descending: false)
                ]
            ),
            ExpectedSchemaIndex(
                name: "idx_clipboard_item_folders_folder_id",
                table: "clipboard_item_folders",
                terms: [
                    ExpectedSchemaIndexTerm(column: "folder_id", descending: false)
                ]
            ),
            ExpectedSchemaIndex(
                name: "idx_clipboard_items_favorite_capture_order",
                table: "clipboard_items",
                terms: [
                    ExpectedSchemaIndexTerm(column: "is_favorite", descending: false),
                    ExpectedSchemaIndexTerm(column: "last_captured_at", descending: true),
                    ExpectedSchemaIndexTerm(column: "timestamp", descending: true)
                ]
            ),
            ExpectedSchemaIndex(
                name: "idx_clipboard_items_usage_order",
                table: "clipboard_items",
                terms: [
                    ExpectedSchemaIndexTerm(column: "usage_count", descending: true),
                    ExpectedSchemaIndexTerm(column: "last_used_at", descending: true),
                    ExpectedSchemaIndexTerm(column: "last_captured_at", descending: true),
                    ExpectedSchemaIndexTerm(column: "timestamp", descending: true)
                ]
            ),
            ExpectedSchemaIndex(
                name: "idx_clipboard_items_duplicate_lookup",
                table: "clipboard_items",
                terms: [
                    ExpectedSchemaIndexTerm(column: "primary_content_type", descending: false),
                    ExpectedSchemaIndexTerm(column: "bundle_id", descending: false),
                    ExpectedSchemaIndexTerm(column: "duplicate_digest", descending: false),
                    ExpectedSchemaIndexTerm(column: "last_captured_at", descending: true),
                    ExpectedSchemaIndexTerm(column: "timestamp", descending: true)
                ]
            )
        ]
    }

    private func assertQueryPathIndexes(
        in db: Connection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for index in expectedQueryPathIndexes() {
            let indexCount = try integerScalar(
                "SELECT COUNT(*) FROM pragma_index_list('\(index.table)') WHERE name = '\(index.name)'",
                in: db
            )
            XCTAssertEqual(indexCount, 1, "\(index.name) should exist on \(index.table)", file: file, line: line)

            let termCount = try integerScalar(
                "SELECT COUNT(*) FROM pragma_index_xinfo('\(index.name)') WHERE key = 1",
                in: db
            )
            XCTAssertEqual(termCount, index.terms.count, "\(index.name) should have expected key columns", file: file, line: line)

            for (seqno, term) in index.terms.enumerated() {
                let descending = term.descending ? 1 : 0
                let matchingTermCount = try integerScalar(
                    """
                    SELECT COUNT(*) FROM pragma_index_xinfo('\(index.name)')
                    WHERE key = 1
                      AND seqno = \(seqno)
                      AND name = '\(term.column)'
                      AND "desc" = \(descending)
                    """,
                    in: db
                )
                XCTAssertEqual(
                    matchingTermCount,
                    1,
                    "\(index.name) should include \(term.column) at seqno \(seqno)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func createSchemaVersionTenTables(in db: Connection) throws {
        try db.run("""
            CREATE TABLE clipboard_items (
                id BLOB PRIMARY KEY NOT NULL,
                content TEXT NOT NULL,
                display_title TEXT,
                timestamp REAL NOT NULL,
                bundle_id TEXT,
                is_secret INTEGER NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                usage_count INTEGER NOT NULL DEFAULT 0,
                last_used_at REAL,
                capture_count INTEGER NOT NULL DEFAULT 1,
                last_captured_at REAL,
                primary_content_type TEXT NOT NULL DEFAULT 'plainText',
                migrated_from_legacy INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.run("""
            CREATE TABLE clipboard_payloads (
                id BLOB PRIMARY KEY NOT NULL,
                item_id BLOB NOT NULL,
                content_type TEXT NOT NULL,
                pasteboard_type TEXT NOT NULL DEFAULT '\(NSPasteboard.PasteboardType.string.rawValue)',
                encrypted_data TEXT NOT NULL,
                byte_size INTEGER NOT NULL DEFAULT 0,
                preview TEXT,
                rank INTEGER NOT NULL DEFAULT 0
            )
            """)
        try db.run("""
            CREATE TABLE clipboard_folders (
                id BLOB PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """)
        try db.run("""
            CREATE TABLE clipboard_item_folders (
                item_id BLOB NOT NULL,
                folder_id BLOB NOT NULL,
                assigned_at REAL NOT NULL
            )
            """)
    }

    private func createSchemaVersionElevenTables(in db: Connection) throws {
        try createSchemaVersionTenTables(in: db)
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_payloads_item_id_rank
            ON clipboard_payloads(item_id, rank)
            """)
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_item_folders_item_id_folder_id
            ON clipboard_item_folders(item_id, folder_id)
            """)
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_item_folders_folder_id
            ON clipboard_item_folders(folder_id)
            """)
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_items_favorite_capture_order
            ON clipboard_items(is_favorite, last_captured_at DESC, timestamp DESC)
            """)
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_clipboard_items_usage_order
            ON clipboard_items(usage_count DESC, last_used_at DESC, last_captured_at DESC, timestamp DESC)
            """)
    }

    private func integerScalar(_ sql: String, in db: Connection) throws -> Int {
        let value = try db.scalar(sql)
        if let intValue = value as? Int64 {
            return Int(intValue)
        }
        if let intValue = value as? Int {
            return intValue
        }
        return 0
    }

    private func assertDatabaseUnavailableAfterSetupFailure(_ manager: DatabaseManager) async {
        let item = ClipboardItem(id: UUID(), content: "should not save", timestamp: Date())
        await assertThrowsPersistenceError {
            try await manager.saveItem(item, originBundleID: nil, secret: false, migrated: false)
        } verify: { error in
            XCTAssertEqual(error, .databaseUnavailable)
        }
    }

    private func assertThrowsPersistenceError(
        _ operation: () async throws -> Void,
        verify: (ClipboardPersistenceError) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected ClipboardPersistenceError", file: file, line: line)
        } catch let error as ClipboardPersistenceError {
            verify(error)
        } catch {
            XCTFail("Expected ClipboardPersistenceError, got \(error)", file: file, line: line)
        }
    }

    private func makeDatabaseManager(
        databaseURL: URL,
        retentionPolicy: ClipboardRetentionPolicy = .load(),
        security: ClipboardCryptographyProviding? = nil,
        payloadQuotaBytes: Int = ClipboardResourceLimits.maxStoredPayloadBytes
    ) -> DatabaseManager {
        DatabaseManager(
            databaseURL: databaseURL,
            retentionPolicy: retentionPolicy,
            security: security ?? self.security,
            payloadQuotaBytes: payloadQuotaBytes
        )
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}

private final class CountingClipboardCryptography: ClipboardCryptographyProviding, @unchecked Sendable {
    private let wrapped = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
    private(set) var decryptCallCount = 0

    var lastError: SecurityManager.SecurityError? {
        wrapped.lastError
    }

    func encrypt(_ text: String, context: EncryptionContext?) -> String? {
        wrapped.encrypt(text, context: context)
    }

    func decrypt(_ base64Encoded: String, context: EncryptionContext?) -> String? {
        decryptCallCount += 1
        return wrapped.decrypt(base64Encoded, context: context)
    }

    func decryptLegacy(_ base64Encoded: String) -> String? {
        decryptCallCount += 1
        return wrapped.decryptLegacy(base64Encoded)
    }

    func duplicateContentDigest(for text: String) -> String? {
        wrapped.duplicateContentDigest(for: text)
    }

    func currentKeyState() -> SecurityKeyState {
        wrapped.currentKeyState()
    }

    func replaceMissingKey() -> Bool {
        wrapped.replaceMissingKey()
    }

    func resetCounters() {
        decryptCallCount = 0
    }
}
#elseif canImport(Testing)
import Testing
@testable import Forkclip

@MainActor
struct DatabaseManagerTests {
    @Test
    func xctestCoverageSentinelDatabaseManagerTestsOnMacOS() async throws {
        #expect(true)
    }
}
#endif
