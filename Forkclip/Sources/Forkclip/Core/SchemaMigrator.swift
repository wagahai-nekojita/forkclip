import AppKit
import Foundation
import SQLite

enum SchemaMigrationError: LocalizedError, Equatable {
    case unsupportedFutureVersion(found: Int, current: Int)
    case legacyItemPayloadMigrationFailed(itemID: UUID)
    case legacyPlainTextPayloadRewriteFailed(payloadID: UUID, itemID: UUID)

    var errorDescription: String? {
        switch self {
        case .unsupportedFutureVersion(let found, let current):
            return "未対応の将来スキーマです。(found: \(found), current: \(current))"
        case .legacyItemPayloadMigrationFailed(let itemID):
            return "legacy item payload migration failed. (itemID: \(itemID.uuidString))"
        case .legacyPlainTextPayloadRewriteFailed(let payloadID, let itemID):
            return "legacy plain text payload rewrite failed. (payloadID: \(payloadID.uuidString), itemID: \(itemID.uuidString))"
        }
    }
}

struct SchemaMigrator {
    static let currentSchemaVersion = 11
    private let security: ClipboardCryptographyProviding

    private let items = Table("clipboard_items")
    private let id = Expression<UUID>("id")
    private let content = Expression<String>("content")
    private let displayTitle = Expression<String?>("display_title")
    private let timestamp = Expression<Date>("timestamp")
    private let bundleID = Expression<String?>("bundle_id")
    private let isSecret = Expression<Bool>("is_secret")
    private let isFavorite = Expression<Bool>("is_favorite")
    private let usageCount = Expression<Int>("usage_count")
    private let lastUsedAt = Expression<Date?>("last_used_at")
    private let captureCount = Expression<Int>("capture_count")
    private let lastCapturedAt = Expression<Date?>("last_captured_at")
    private let primaryContentType = Expression<String>("primary_content_type")
    private let migratedFromLegacy = Expression<Bool>("migrated_from_legacy")

    private let payloads = Table("clipboard_payloads")
    private let payloadID = Expression<UUID>("id")
    private let payloadItemID = Expression<UUID>("item_id")
    private let payloadContentType = Expression<String>("content_type")
    private let payloadPasteboardType = Expression<String>("pasteboard_type")
    private let payloadEncryptedData = Expression<String>("encrypted_data")
    private let payloadByteSize = Expression<Int>("byte_size")
    private let payloadPreview = Expression<String?>("preview")
    private let payloadRank = Expression<Int>("rank")

    private let folders = Table("clipboard_folders")
    private let folderID = Expression<UUID>("id")
    private let folderName = Expression<String>("name")
    private let folderColor = Expression<String>("color")
    private let folderSortOrder = Expression<Int>("sort_order")
    private let folderCreatedAt = Expression<Date>("created_at")
    private let folderUpdatedAt = Expression<Date>("updated_at")

    private let itemFolders = Table("clipboard_item_folders")
    private let itemFolderItemID = Expression<UUID>("item_id")
    private let itemFolderFolderID = Expression<UUID>("folder_id")
    private let itemFolderAssignedAt = Expression<Date>("assigned_at")

    init(security: ClipboardCryptographyProviding = SecurityManager.shared) {
        self.security = security
    }

    func migrate(in db: Connection) throws {
        let version = try userVersion(in: db)
        if version > Self.currentSchemaVersion {
            throw SchemaMigrationError.unsupportedFutureVersion(found: version, current: Self.currentSchemaVersion)
        }

        try db.transaction {
            try createCurrentTablesIfNeeded(in: db)

            if version < 1 { try addFavoriteColumnIfNeeded(in: db) }
            if version < 2 { try addUsageColumnsIfNeeded(in: db) }
            if version < 3 { try addPrimaryContentTypeColumnIfNeeded(in: db) }
            if version < 4 { try addPayloadPasteboardTypeColumnIfNeeded(in: db) }
            if version < 5 { try clearPayloadPreviews(in: db) }
            if version < 6 { try backfillPrimaryContentTypesFromPayloads(in: db) }
            if version < 7 { try migrateTextContentToPayloadsIfNeeded(in: db) }
            if version < 8 { try migrateLegacyPlainTextPayloadEncodingIfNeeded(in: db) }
            if version < 9 { try addCaptureColumnsIfNeeded(in: db) }
            if version < 10 { try addDisplayTitleColumnIfNeeded(in: db) }
            if version < 11 { try addQueryPathIndexesIfNeeded(in: db) }

            try setUserVersion(Self.currentSchemaVersion, in: db)
        }
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

    private func setUserVersion(_ version: Int, in db: Connection) throws {
        try db.run("PRAGMA user_version = \(version)")
    }

    private func createCurrentTablesIfNeeded(in db: Connection) throws {
        try db.run(items.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(content)
            t.column(displayTitle)
            t.column(timestamp)
            t.column(bundleID)
            t.column(isSecret)
            t.column(isFavorite, defaultValue: false)
            t.column(usageCount, defaultValue: 0)
            t.column(lastUsedAt)
            t.column(captureCount, defaultValue: 1)
            t.column(lastCapturedAt)
            t.column(primaryContentType, defaultValue: ClipboardContentType.plainText.rawValue)
            t.column(migratedFromLegacy, defaultValue: false)
        })

        try db.run(payloads.create(ifNotExists: true) { t in
            t.column(payloadID, primaryKey: true)
            t.column(payloadItemID)
            t.column(payloadContentType)
            t.column(payloadPasteboardType, defaultValue: NSPasteboard.PasteboardType.string.rawValue)
            t.column(payloadEncryptedData)
            t.column(payloadByteSize, defaultValue: 0)
            t.column(payloadPreview)
            t.column(payloadRank, defaultValue: 0)
        })

        try db.run(folders.create(ifNotExists: true) { t in
            t.column(folderID, primaryKey: true)
            t.column(folderName)
            t.column(folderColor)
            t.column(folderSortOrder, defaultValue: 0)
            t.column(folderCreatedAt)
            t.column(folderUpdatedAt)
        })

        try db.run(itemFolders.create(ifNotExists: true) { t in
            t.column(itemFolderItemID)
            t.column(itemFolderFolderID)
            t.column(itemFolderAssignedAt)
        })
    }

    private func addQueryPathIndexesIfNeeded(in db: Connection) throws {
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

    private func addFavoriteColumnIfNeeded(in db: Connection) throws {
        let count = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'is_favorite'") as? Int64 ?? 0
        guard count == 0 else { return }
        try db.run(items.addColumn(isFavorite, defaultValue: false))
    }

    private func addUsageColumnsIfNeeded(in db: Connection) throws {
        let usageCountColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'usage_count'") as? Int64 ?? 0
        if usageCountColumnCount == 0 {
            try db.run(items.addColumn(usageCount, defaultValue: 0))
        }

        let lastUsedAtColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'last_used_at'") as? Int64 ?? 0
        if lastUsedAtColumnCount == 0 {
            try db.run(items.addColumn(lastUsedAt))
        }
    }

    private func addCaptureColumnsIfNeeded(in db: Connection) throws {
        let captureCountColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'capture_count'") as? Int64 ?? 0
        if captureCountColumnCount == 0 {
            try db.run(items.addColumn(captureCount, defaultValue: 1))
        }

        let lastCapturedAtColumnCount = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'last_captured_at'") as? Int64 ?? 0
        if lastCapturedAtColumnCount == 0 {
            try db.run(items.addColumn(lastCapturedAt))
        }

        try db.run("UPDATE clipboard_items SET last_captured_at = timestamp WHERE last_captured_at IS NULL")
    }

    private func addDisplayTitleColumnIfNeeded(in db: Connection) throws {
        let count = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'display_title'") as? Int64 ?? 0
        guard count == 0 else { return }
        try db.run(items.addColumn(displayTitle))
    }

    private func addPrimaryContentTypeColumnIfNeeded(in db: Connection) throws {
        let count = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_items') WHERE name = 'primary_content_type'") as? Int64 ?? 0
        guard count == 0 else { return }
        try db.run(items.addColumn(primaryContentType, defaultValue: ClipboardContentType.plainText.rawValue))
    }

    private func addPayloadPasteboardTypeColumnIfNeeded(in db: Connection) throws {
        let count = try db.scalar("SELECT COUNT(*) FROM pragma_table_info('clipboard_payloads') WHERE name = 'pasteboard_type'") as? Int64 ?? 0
        guard count == 0 else { return }
        try db.run(payloads.addColumn(payloadPasteboardType, defaultValue: NSPasteboard.PasteboardType.string.rawValue))
    }

    private func clearPayloadPreviews(in db: Connection) throws {
        try db.run("UPDATE clipboard_payloads SET preview = NULL WHERE preview IS NOT NULL")
    }

    private func backfillPrimaryContentTypesFromPayloads(in db: Connection) throws {
        let rows = try db.prepare(payloads.select(payloadItemID, payloadContentType, payloadRank).order(payloadItemID.asc, payloadRank.asc))
        var rankedTypesByItemID: [UUID: [ClipboardContentType]] = [:]
        for row in rows {
            let itemID = row[payloadItemID]
            guard let contentType = ClipboardContentType(rawValue: row[payloadContentType]) else {
                continue
            }
            rankedTypesByItemID[itemID, default: []].append(contentType)
        }

        let itemRows = try db.prepare(items.select(id, primaryContentType))
        for itemRow in itemRows {
            let itemID = itemRow[id]
            let currentType = ClipboardContentType(rawValue: itemRow[primaryContentType]) ?? .plainText
            guard let rankedTypes = rankedTypesByItemID[itemID],
                  let contentType = backfilledPrimaryContentType(current: currentType, rankedPayloadTypes: rankedTypes),
                  contentType != currentType else {
                continue
            }
            try db.run(
                items
                    .filter(id == itemID && primaryContentType == currentType.rawValue)
                    .update(primaryContentType <- contentType.rawValue)
            )
        }
    }

    private func backfilledPrimaryContentType(
        current: ClipboardContentType,
        rankedPayloadTypes: [ClipboardContentType]
    ) -> ClipboardContentType? {
        if current == .fileURL, rankedPayloadTypes.contains(.image) {
            return .image
        }
        guard current == .plainText else {
            return nil
        }
        if rankedPayloadTypes.first == .fileURL, rankedPayloadTypes.contains(.image) {
            return .image
        }
        return rankedPayloadTypes.first
    }

    private func migrateTextContentToPayloadsIfNeeded(in db: Connection) throws {
        for itemRow in try db.prepare(items) {
            let existingPayloads = payloads.filter(payloadItemID == itemRow[id])
            guard try db.scalar(existingPayloads.count) == 0 else { continue }
            let itemID = itemRow[id]
            let newPayloadID = UUID()
            guard let decryptedContent = security.decrypt(
                    itemRow[content],
                    context: .itemContent(itemID: itemID)
                  ),
                  let encryptedPayload = encryptedBase64PayloadData(
                    for: Data(decryptedContent.utf8),
                    itemID: itemID,
                    payloadID: newPayloadID
                  ) else {
                AppLogger.database.error("Legacy text payload migration failed because item content could not be re-encoded.")
                throw SchemaMigrationError.legacyItemPayloadMigrationFailed(itemID: itemID)
            }

            try db.run(payloads.insert(
                payloadID <- newPayloadID,
                payloadItemID <- itemID,
                payloadContentType <- ClipboardContentType.plainText.rawValue,
                payloadPasteboardType <- NSPasteboard.PasteboardType.string.rawValue,
                payloadEncryptedData <- encryptedPayload,
                payloadByteSize <- decryptedContent.utf8.count,
                payloadPreview <- nil,
                payloadRank <- 0
            ))
        }
    }

    private func migrateLegacyPlainTextPayloadEncodingIfNeeded(in db: Connection) throws {
        let legacyRows = try db.prepare(
            payloads
                .select(payloadID, payloadItemID, payloadEncryptedData)
                .filter(payloadContentType == ClipboardContentType.plainText.rawValue)
        )

        var rewrites: [(id: UUID, encryptedData: String, byteSize: Int)] = []
        for row in legacyRows {
            let itemID = row[payloadItemID]
            let legacyPayloadID = row[payloadID]
            guard let payloadText = security.decrypt(
                row[payloadEncryptedData],
                context: .payloadData(itemID: itemID, payloadID: legacyPayloadID)
            ) else {
                AppLogger.database.error("Legacy plain text payload rewrite failed because payload data could not be decrypted.")
                throw SchemaMigrationError.legacyPlainTextPayloadRewriteFailed(payloadID: legacyPayloadID, itemID: itemID)
            }
            guard let itemRow = try db.pluck(items.select(content).filter(id == itemID)),
                  let itemText = security.decrypt(
                    itemRow[content],
                    context: .itemContent(itemID: itemID)
                  ) else {
                AppLogger.database.error("Legacy plain text payload rewrite failed because item content could not be decrypted.")
                throw SchemaMigrationError.legacyPlainTextPayloadRewriteFailed(payloadID: legacyPayloadID, itemID: itemID)
            }
            guard payloadText == itemText else {
                continue
            }
            guard let encryptedPayload = encryptedBase64PayloadData(
                for: Data(itemText.utf8),
                itemID: itemID,
                payloadID: legacyPayloadID
            ) else {
                AppLogger.database.error("Legacy plain text payload rewrite failed because payload data could not be re-encoded.")
                throw SchemaMigrationError.legacyPlainTextPayloadRewriteFailed(payloadID: legacyPayloadID, itemID: itemID)
            }
            rewrites.append((legacyPayloadID, encryptedPayload, itemText.utf8.count))
        }

        for rewrite in rewrites {
            try db.run(
                payloads
                    .filter(payloadID == rewrite.id)
                    .update(
                        payloadEncryptedData <- rewrite.encryptedData,
                        payloadByteSize <- rewrite.byteSize
                    )
            )
        }
    }

    private func encryptedBase64PayloadData(for data: Data, itemID: UUID, payloadID: UUID) -> String? {
        security.encrypt(
            data.base64EncodedString(),
            context: .payloadData(itemID: itemID, payloadID: payloadID)
        )
    }
}
