import Foundation
import AppKit
import SQLite

struct DiagnosticsSnapshot: Sendable {
    let databasePath: String?
    let databaseStatus: DatabaseStatus
    let fetchFailureCount: Int
    let keyState: SecurityKeyState
    let securityErrorDescription: String?
    let lastRecoveryBackupPath: String?
    var monitorState: ClipboardMonitorState
    var lastObservedChangeCount: Int?
    var lastProcessedChangeAt: Date?
    var lastSaveStatus: ClipboardOperationStatus
    var lastSaveError: String?
}

extension DiagnosticsSnapshot {
    static func initial(databasePath: String? = nil) -> DiagnosticsSnapshot {
        DiagnosticsSnapshot(
            databasePath: databasePath,
            databaseStatus: .uninitialized,
            fetchFailureCount: 0,
            keyState: .unchecked,
            securityErrorDescription: nil,
            lastRecoveryBackupPath: nil,
            monitorState: .unchecked,
            lastObservedChangeCount: nil,
            lastProcessedChangeAt: nil,
            lastSaveStatus: .notRun,
            lastSaveError: nil
        )
    }
}

struct ClipboardRetentionPolicy: Codable, Equatable, Sendable {
    let fetchLimit: Int
    let maxStoredItems: Int?
    let maxAgeDays: Int?

    init(
        fetchLimit: Int = AppSettings.defaultFetchLimit,
        maxStoredItems: Int? = nil,
        maxAgeDays: Int? = nil
    ) {
        self.fetchLimit = max(1, fetchLimit)
        self.maxStoredItems = maxStoredItems.map { max(1, $0) }
        self.maxAgeDays = maxAgeDays.map { max(1, $0) }
    }

    static func load(from url: URL? = nil) -> ClipboardRetentionPolicy {
        let policyURL = url ?? (try? AppPaths.retentionPolicyURL())
        guard let policyURL, FileManager.default.fileExists(atPath: policyURL.path) else {
            return ClipboardRetentionPolicy()
        }

        do {
            let data = try Data(contentsOf: policyURL)
            return try JSONDecoder().decode(ClipboardRetentionPolicy.self, from: data)
        } catch {
            AppLogger.database.error("Failed to load retention policy: \(String(describing: error), privacy: .public)")
            return ClipboardRetentionPolicy()
        }
    }
}

struct SQLiteConnectionPragmas: Equatable, Sendable {
    let journalMode: String
    let busyTimeoutMilliseconds: Int
}

private enum DatabaseConnectionPragmaError: LocalizedError, Equatable, Sendable {
    case invalidValue(name: String, value: String)
    case unexpectedJournalMode(expected: String, actual: String)
    case unexpectedBusyTimeout(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let name, let value):
            return "SQLite PRAGMA \(name) returned unsupported value: \(value)."
        case .unexpectedJournalMode(let expected, let actual):
            return "SQLite PRAGMA journal_mode expected \(expected), got \(actual)."
        case .unexpectedBusyTimeout(let expected, let actual):
            return "SQLite PRAGMA busy_timeout expected \(expected), got \(actual)."
        }
    }
}

actor DatabaseManager {
    nonisolated static let shared = DatabaseManager(
        databaseURL: nil,
        retentionPolicy: .load(),
        security: SecurityManager.shared
    )
    private static let expectedSQLiteJournalMode = "wal"
    private static let sqliteBusyTimeoutMilliseconds = 5_000
    private let databaseURLOverride: URL?
    private let security: ClipboardCryptographyProviding
    private var retentionPolicy: ClipboardRetentionPolicy
    private var db: Connection?
    private(set) var lastFetchFailureCount = 0
    private(set) var lastRecoveryBackupURL: URL?
    private(set) var databaseStatus: DatabaseStatus = .uninitialized

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
    private struct PendingPayloadInsert {
        let insert: Insert
        let contentType: ClipboardContentType
        let pasteboardType: String
    }

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

    init(
        databaseURL: URL? = nil,
        retentionPolicy: ClipboardRetentionPolicy = .load(),
        security: ClipboardCryptographyProviding = SecurityManager.shared
    ) {
        self.databaseURLOverride = databaseURL
        self.security = security
        self.retentionPolicy = retentionPolicy
    }

    private func ensureDatabaseSetup() {
        guard db == nil, databaseStatus == .uninitialized else { return }
        setupDatabase()
    }

    private func setupDatabase() {
        do {
            let databaseURL = try currentDatabaseURL()
            let openedDatabase = try Connection(databaseURL.path)
            try AppPaths.applyOwnerOnlyFilePermissions(to: databaseURL)
            try configureConnectionPragmas(in: openedDatabase)
            AppLogger.database.notice("Database opened at \(databaseURL.path, privacy: .public)")

            try SchemaMigrator(security: security).migrate(in: openedDatabase)
            try applyRetentionPolicy(in: openedDatabase)

            db = openedDatabase
            databaseStatus = .available
        } catch {
            db = nil
            databaseStatus = .failed
            AppLogger.database.error("Database setup error: \(String(describing: error), privacy: .public)")
        }
    }

    func connectionPragmas() throws -> SQLiteConnectionPragmas {
        ensureDatabaseSetup()
        guard let db else {
            throw ClipboardPersistenceError.databaseUnavailable
        }
        return try readConnectionPragmas(in: db)
    }

    func saveItem(_ item: ClipboardItem, originBundleID: String?, secret: Bool, migrated: Bool = false) async throws {
        try await saveItem(item, payloads: [.plainText(item.content)], originBundleID: originBundleID, secret: secret, migrated: migrated)
    }

    func saveItem(_ item: ClipboardItem, payloads itemPayloads: [ClipboardPayload], originBundleID: String?, secret: Bool, migrated: Bool = false) async throws {
        ensureDatabaseSetup()
        guard let db else {
            AppLogger.database.error("Save aborted because database is unavailable.")
            throw ClipboardPersistenceError.databaseUnavailable
        }
        guard let encrypted = security.encrypt(
            item.content,
            context: .itemContent(itemID: item.id)
        ) else {
            AppLogger.database.error("Save aborted because encryption failed.")
            throw ClipboardPersistenceError.itemEncryptionFailed(security.lastError)
        }
        let normalizedDisplayTitle = ClipboardItem.normalizedDisplayTitle(item.displayTitle)
        let encryptedDisplayTitle: String?
        if let normalizedDisplayTitle {
            guard let encrypted = security.encrypt(
                normalizedDisplayTitle,
                context: .itemDisplayTitle(itemID: item.id)
            ) else {
                AppLogger.database.error("Save aborted because display title encryption failed.")
                throw ClipboardPersistenceError.displayTitleEncryptionFailed(security.lastError)
            }
            encryptedDisplayTitle = encrypted
        } else {
            encryptedDisplayTitle = nil
        }

        let payloadsToStore = itemPayloads.isEmpty ? [.plainText(item.content)] : itemPayloads
        var payloadInserts: [PendingPayloadInsert] = []
        for payload in payloadsToStore {
            payloadInserts.append(try payloadInsert(for: payload, itemID: item.id))
        }

        let insert = items.insert(
            id <- item.id,
            content <- encrypted,
            displayTitle <- encryptedDisplayTitle,
            timestamp <- item.timestamp,
            bundleID <- originBundleID,
            isSecret <- secret,
            isFavorite <- item.isFavorite,
            usageCount <- item.usageCount,
            lastUsedAt <- item.lastUsedAt,
            captureCount <- item.captureCount,
            lastCapturedAt <- Optional(item.lastCapturedAt),
            primaryContentType <- item.primaryContentType.rawValue,
            migratedFromLegacy <- migrated
        )
        do {
            try db.run("BEGIN DEFERRED TRANSACTION")
            do {
                do {
                    try db.run(insert)
                } catch {
                    throw ClipboardPersistenceError.itemWriteFailed(String(describing: error))
                }
                for payloadInsert in payloadInserts {
                    do {
                        try db.run(payloadInsert.insert)
                    } catch {
                        throw ClipboardPersistenceError.payloadWriteFailed(
                            contentType: payloadInsert.contentType,
                            pasteboardType: payloadInsert.pasteboardType,
                            underlying: String(describing: error)
                        )
                    }
                }
                do {
                    try applyRetentionPolicy(in: db)
                } catch {
                    throw ClipboardPersistenceError.retentionPolicyFailed(String(describing: error))
                }
                try db.run("COMMIT TRANSACTION")
            } catch {
                _ = try? db.run("ROLLBACK TRANSACTION")
                throw error
            }
            AppLogger.database.debug("Saved clipboard item \(item.id.uuidString, privacy: .public)")
        } catch let persistenceError as ClipboardPersistenceError {
            AppLogger.database.error("Save error: \(persistenceError.localizedDescription, privacy: .public)")
            throw persistenceError
        } catch {
            AppLogger.database.error("Save error: \(String(describing: error), privacy: .public)")
            throw ClipboardPersistenceError.databaseWriteFailed(String(describing: error))
        }
    }

    func payloads(for itemID: UUID) async -> [ClipboardPayload] {
        ensureDatabaseSetup()
        guard let db else { return [] }
        do {
            let query = payloads
                .filter(payloadItemID == itemID)
                .order(payloadRank.asc)
            return try db.prepare(query).compactMap { row in
                clipboardPayload(from: row)
            }
        } catch {
            AppLogger.database.error("Fetch payloads error: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func deleteItem(withID itemID: UUID) {
        ensureDatabaseSetup()
        guard let db else { return }
        do {
            let target = items.filter(id == itemID)
            let targetPayloads = payloads.filter(payloadItemID == itemID)
            let targetFolders = itemFolders.filter(itemFolderItemID == itemID)
            try db.run("BEGIN DEFERRED TRANSACTION")
            do {
                try db.run(targetPayloads.delete())
                try db.run(targetFolders.delete())
                try db.run(target.delete())
                try db.run("COMMIT TRANSACTION")
            } catch {
                _ = try? db.run("ROLLBACK TRANSACTION")
                throw error
            }
            AppLogger.database.debug("Deleted clipboard item \(itemID.uuidString, privacy: .public)")
        } catch {
            AppLogger.database.error("Delete error: \(String(describing: error), privacy: .public)")
        }
    }

    func fetchFolders() -> [ClipboardFolder] {
        ensureDatabaseSetup()
        guard let db else { return [] }
        do {
            return try db.prepare(folders.order(folderSortOrder.asc, folderName.asc)).map { row in
                ClipboardFolder(
                    id: row[folderID],
                    name: row[folderName],
                    color: row[folderColor],
                    sortOrder: row[folderSortOrder],
                    createdAt: row[folderCreatedAt],
                    updatedAt: row[folderUpdatedAt]
                )
            }
        } catch {
            AppLogger.database.error("Fetch folders error: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    func fetchFolderAssignments() -> [UUID: Set<UUID>] {
        ensureDatabaseSetup()
        guard let db else { return [:] }
        do {
            var assignments: [UUID: Set<UUID>] = [:]
            for row in try db.prepare(itemFolders) {
                assignments[row[itemFolderItemID], default: []].insert(row[itemFolderFolderID])
            }
            return assignments
        } catch {
            AppLogger.database.error("Fetch folder assignments error: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    func createFolder(named name: String, color: String = "#4A90E2") -> ClipboardFolder? {
        ensureDatabaseSetup()
        guard let db else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        do {
            let nextSortOrder = ((try db.pluck(folders.order(folderSortOrder.desc).limit(1)))?[folderSortOrder] ?? -1) + 1
            let folder = ClipboardFolder(name: trimmedName, color: color, sortOrder: nextSortOrder)
            try db.run(folders.insert(
                folderID <- folder.id,
                folderName <- folder.name,
                folderColor <- folder.color,
                folderSortOrder <- folder.sortOrder,
                folderCreatedAt <- folder.createdAt,
                folderUpdatedAt <- folder.updatedAt
            ))
            return folder
        } catch {
            AppLogger.database.error("Create folder error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    @discardableResult
    func updateFolder(_ folder: ClipboardFolder) -> Bool {
        ensureDatabaseSetup()
        guard let db else { return false }
        let trimmedName = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        do {
            let target = folders.filter(folderID == folder.id)
            try db.run(target.update(
                folderName <- trimmedName,
                folderColor <- folder.color,
                folderSortOrder <- folder.sortOrder,
                folderUpdatedAt <- Date()
            ))
            return true
        } catch {
            AppLogger.database.error("Update folder error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func deleteFolder(withID id: UUID) {
        ensureDatabaseSetup()
        guard let db else { return }
        do {
            try db.run("BEGIN DEFERRED TRANSACTION")
            do {
                try db.run(itemFolders.filter(itemFolderFolderID == id).delete())
                try db.run(folders.filter(folderID == id).delete())
                try db.run("COMMIT TRANSACTION")
            } catch {
                _ = try? db.run("ROLLBACK TRANSACTION")
                throw error
            }
        } catch {
            AppLogger.database.error("Delete folder error: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    func assignItem(_ itemID: UUID, toFolder folderID: UUID) -> Bool {
        ensureDatabaseSetup()
        guard let db else { return false }
        do {
            let existing = itemFolders
                .filter(itemFolderItemID == itemID && itemFolderFolderID == folderID)
            guard try db.scalar(existing.count) == 0 else { return true }
            try db.run(itemFolders.insert(
                itemFolderItemID <- itemID,
                itemFolderFolderID <- folderID,
                itemFolderAssignedAt <- Date()
            ))
            return true
        } catch {
            AppLogger.database.error("Assign folder error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func unassignItem(_ itemID: UUID, fromFolder folderID: UUID) {
        ensureDatabaseSetup()
        guard let db else { return }
        do {
            try db.run(itemFolders
                .filter(itemFolderItemID == itemID && itemFolderFolderID == folderID)
                .delete())
        } catch {
            AppLogger.database.error("Unassign folder error: \(String(describing: error), privacy: .public)")
        }
    }

    func unassignItemFromAllFolders(_ itemID: UUID) {
        ensureDatabaseSetup()
        guard let db else { return }
        do {
            try db.run(itemFolders.filter(itemFolderItemID == itemID).delete())
        } catch {
            AppLogger.database.error("Unassign all folders error: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    func reorderFolders(_ orderedFolders: [ClipboardFolder]) -> Bool {
        ensureDatabaseSetup()
        guard let db else { return false }
        do {
            try db.run("BEGIN DEFERRED TRANSACTION")
            do {
                for (index, folder) in orderedFolders.enumerated() {
                    try db.run(folders
                        .filter(folderID == folder.id)
                        .update(folderSortOrder <- index, folderUpdatedAt <- Date()))
                }
                try db.run("COMMIT TRANSACTION")
            } catch {
                _ = try? db.run("ROLLBACK TRANSACTION")
                throw error
            }
            return true
        } catch {
            AppLogger.database.error("Reorder folders error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func updateFavoriteState(for itemID: UUID, isFavorite: Bool) -> Bool {
        ensureDatabaseSetup()
        guard let db else { return false }
        do {
            let updatedRows = try db.run(items.filter(id == itemID).update(self.isFavorite <- isFavorite))
            return updatedRows > 0
        } catch {
            AppLogger.database.error("Update favorite error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func updateSecretState(for itemID: UUID, isSecret: Bool) -> Bool {
        ensureDatabaseSetup()
        guard let db else { return false }
        do {
            let updatedRows = try db.run(items.filter(id == itemID).update(self.isSecret <- isSecret))
            return updatedRows > 0
        } catch {
            AppLogger.database.error("Update secret state error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func updateDisplayTitle(for itemID: UUID, displayTitle: String?) -> Bool {
        ensureDatabaseSetup()
        guard let db else { return false }
        let normalizedDisplayTitle = ClipboardItem.normalizedDisplayTitle(displayTitle)
        let encryptedDisplayTitle: String?
        if let normalizedDisplayTitle {
            guard let encrypted = security.encrypt(
                normalizedDisplayTitle,
                context: .itemDisplayTitle(itemID: itemID)
            ) else {
                AppLogger.database.error("Update display title aborted because encryption failed.")
                return false
            }
            encryptedDisplayTitle = encrypted
        } else {
            encryptedDisplayTitle = nil
        }

        do {
            let updatedRows = try db.run(items.filter(id == itemID).update(self.displayTitle <- encryptedDisplayTitle))
            return updatedRows > 0
        } catch {
            AppLogger.database.error("Update display title error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    @discardableResult
    func recordDuplicateCapture(content: String, primaryContentType: ClipboardContentType, bundleID: String?, at date: Date) async -> ClipboardItem? {
        ensureDatabaseSetup()
        guard let db else { return nil }
        do {
            var candidateQuery = items.filter(self.primaryContentType == primaryContentType.rawValue)
            if let bundleID {
                candidateQuery = candidateQuery.filter(self.bundleID == bundleID)
            } else {
                candidateQuery = candidateQuery.filter(self.bundleID == nil)
            }

            for itemRow in try db.prepare(candidateQuery.order(lastCapturedAt.desc, timestamp.desc)) {
                guard var item = try clipboardItem(from: itemRow, in: db),
                      item.content == content else {
                    continue
                }
                let target = items.filter(id == item.id)
                let nextCaptureCount = max(1, itemRow[captureCount]) + 1
                try db.run(target.update(
                    captureCount <- nextCaptureCount,
                    lastCapturedAt <- Optional(date)
                ))
                item.captureCount = nextCaptureCount
                item.lastCapturedAt = date
                return item
            }
        } catch {
            AppLogger.database.error("Record duplicate capture error: \(String(describing: error), privacy: .public)")
        }
        return nil
    }

    @discardableResult
    func recordUse(for itemID: UUID, at date: Date) -> ClipboardItem? {
        ensureDatabaseSetup()
        guard let db else { return nil }
        do {
            let target = items.filter(id == itemID)
            guard let itemRow = try db.pluck(target) else { return nil }
            guard var item = try clipboardItem(from: itemRow, in: db) else { return nil }
            let nextUsageCount = itemRow[usageCount] + 1
            try db.run(target.update(
                usageCount <- nextUsageCount,
                lastUsedAt <- Optional(date)
            ))
            item.usageCount = nextUsageCount
            item.lastUsedAt = date
            return item
        } catch {
            AppLogger.database.error("Record usage error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func fetchAll() -> [ClipboardItem] {
        ensureDatabaseSetup()
        var results: [ClipboardItem] = []
        var failureCount = 0
        do {
            if let db = db {
                let favoriteRows = try db.prepare(items.filter(isFavorite == true).order(lastCapturedAt.desc, timestamp.desc)).map { $0 }
                let recentRows = try db.prepare(items.filter(isFavorite == false).order(lastCapturedAt.desc, timestamp.desc).limit(retentionPolicy.fetchLimit)).map { $0 }
                let usedRows = try db.prepare(
                    items
                        .filter(usageCount > 0)
                        .order(usageCount.desc, lastUsedAt.desc, lastCapturedAt.desc, timestamp.desc)
                        .limit(retentionPolicy.fetchLimit)
                ).map { $0 }
                let uniqueRows = (favoriteRows + recentRows + usedRows).reduce(into: [UUID: Row]()) { rowsByID, row in
                    rowsByID[row[id]] = row
                }
                let rows = uniqueRows.values.sorted { capturedAt(for: $0) > capturedAt(for: $1) }

                for itemRow in rows {
                    if let item = try clipboardItem(from: itemRow, in: db) {
                        results.append(item)
                    } else {
                        failureCount += 1
                    }
                }
            }
        } catch {
            AppLogger.database.error("Fetch error: \(String(describing: error), privacy: .public)")
        }
        lastFetchFailureCount = failureCount
        if failureCount > 0 {
            AppLogger.database.error("Fetch completed with \(failureCount) decryption failures.")
        }
        return results
    }

    private func capturedAt(for itemRow: Row) -> Date {
        itemRow[lastCapturedAt] ?? itemRow[timestamp]
    }

    private func clipboardItem(from itemRow: Row, in db: Connection) throws -> ClipboardItem? {
        guard let decrypted = security.decrypt(
            itemRow[content],
            context: .itemContent(itemID: itemRow[id])
        ) else {
            return nil
        }
        let decryptedDisplayTitle: String?
        if let encryptedDisplayTitle = itemRow[displayTitle] {
            guard let decrypted = security.decrypt(
                encryptedDisplayTitle,
                context: .itemDisplayTitle(itemID: itemRow[id])
            ) else {
                return nil
            }
            decryptedDisplayTitle = ClipboardItem.normalizedDisplayTitle(decrypted)
        } else {
            decryptedDisplayTitle = nil
        }
        return ClipboardItem(
            id: itemRow[id],
            content: decrypted,
            timestamp: itemRow[timestamp],
            displayTitle: decryptedDisplayTitle,
            bundleID: itemRow[bundleID],
            isSecret: itemRow[isSecret],
            isFavorite: itemRow[isFavorite],
            usageCount: itemRow[usageCount],
            lastUsedAt: itemRow[lastUsedAt],
            captureCount: itemRow[captureCount],
            lastCapturedAt: capturedAt(for: itemRow),
            primaryContentType: ClipboardContentType(rawValue: itemRow[primaryContentType]) ?? .plainText
        )
    }

    func diagnosticsSnapshot() -> DiagnosticsSnapshot {
        ensureDatabaseSetup()
        return DiagnosticsSnapshot(
            databasePath: try? currentDatabaseURL().path,
            databaseStatus: databaseStatus,
            fetchFailureCount: lastFetchFailureCount,
            keyState: security.currentKeyState(),
            securityErrorDescription: security.lastError?.localizedDescription,
            lastRecoveryBackupPath: lastRecoveryBackupURL?.path,
            monitorState: .unchecked,
            lastObservedChangeCount: nil,
            lastProcessedChangeAt: nil,
            lastSaveStatus: .notRun,
            lastSaveError: nil
        )
    }

    func updateRetentionPolicy(_ policy: ClipboardRetentionPolicy) {
        retentionPolicy = policy
        ensureDatabaseSetup()
        guard let db else { return }
        do {
            try applyRetentionPolicy(in: db)
        } catch {
            AppLogger.database.error("Apply updated retention policy error: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    func recoverFromMissingKey() -> Bool {
        do {
            let databaseURL = try currentDatabaseURL()
            let backupDirectory = try AppPaths.backupsDirectory()
            let formatter = ISO8601DateFormatter()
            let backupURL = backupDirectory
                .appendingPathComponent("forkclip-recovery-\(formatter.string(from: Date()))")
                .appendingPathExtension("sqlite")

            db = nil

            if AppPaths.fileExists(at: databaseURL) {
                try FileManager.default.moveItem(at: databaseURL, to: backupURL)
                try AppPaths.applyOwnerOnlyFilePermissions(to: backupURL)
                lastRecoveryBackupURL = backupURL
                AppLogger.database.notice("Database archived for recovery at \(backupURL.path, privacy: .public)")
            }

            guard security.replaceMissingKey() else {
                setupDatabase()
                return false
            }

            setupDatabase()
            lastFetchFailureCount = 0
            return true
        } catch {
            AppLogger.database.error("Recovery from missing key failed: \(String(describing: error), privacy: .public)")
            setupDatabase()
            return false
        }
    }

    private func currentDatabaseURL() throws -> URL {
        if let databaseURLOverride {
            return databaseURLOverride
        }
        return try AppPaths.databaseURL()
    }

    private func configureConnectionPragmas(in db: Connection) throws {
        let appliedJournalMode = try setJournalModeToWAL(in: db)
        guard appliedJournalMode.lowercased() == Self.expectedSQLiteJournalMode else {
            throw DatabaseConnectionPragmaError.unexpectedJournalMode(
                expected: Self.expectedSQLiteJournalMode,
                actual: appliedJournalMode
            )
        }

        try db.run("PRAGMA busy_timeout = \(Self.sqliteBusyTimeoutMilliseconds)")
        let appliedBusyTimeout = try busyTimeout(in: db)
        guard appliedBusyTimeout == Self.sqliteBusyTimeoutMilliseconds else {
            throw DatabaseConnectionPragmaError.unexpectedBusyTimeout(
                expected: Self.sqliteBusyTimeoutMilliseconds,
                actual: appliedBusyTimeout
            )
        }
    }

    private func readConnectionPragmas(in db: Connection) throws -> SQLiteConnectionPragmas {
        SQLiteConnectionPragmas(
            journalMode: try journalMode(in: db),
            busyTimeoutMilliseconds: try busyTimeout(in: db)
        )
    }

    private func setJournalModeToWAL(in db: Connection) throws -> String {
        let value = try db.scalar("PRAGMA journal_mode = WAL")
        guard let journalMode = value as? String else {
            throw DatabaseConnectionPragmaError.invalidValue(
                name: "journal_mode",
                value: String(describing: value)
            )
        }
        return journalMode
    }

    private func journalMode(in db: Connection) throws -> String {
        let value = try db.scalar("PRAGMA journal_mode")
        guard let journalMode = value as? String else {
            throw DatabaseConnectionPragmaError.invalidValue(
                name: "journal_mode",
                value: String(describing: value)
            )
        }
        return journalMode
    }

    private func busyTimeout(in db: Connection) throws -> Int {
        let value = try db.scalar("PRAGMA busy_timeout")
        if let intValue = value as? Int64 {
            return Int(intValue)
        }
        if let intValue = value as? Int {
            return intValue
        }
        throw DatabaseConnectionPragmaError.invalidValue(
            name: "busy_timeout",
            value: String(describing: value)
        )
    }

    private func payloadInsert(for payload: ClipboardPayload, itemID: UUID) throws -> PendingPayloadInsert {
        guard let encryptedPayload = encryptedBase64PayloadData(
            for: payload.data,
            itemID: itemID,
            payloadID: payload.id
        ) else {
            AppLogger.database.error("Save aborted because payload encryption failed.")
            throw ClipboardPersistenceError.payloadEncryptionFailed(
                contentType: payload.contentType,
                pasteboardType: payload.pasteboardType.rawValue,
                securityError: security.lastError
            )
        }
        return PendingPayloadInsert(
            insert: payloads.insert(
                payloadID <- payload.id,
                payloadItemID <- itemID,
                payloadContentType <- payload.contentType.rawValue,
                payloadPasteboardType <- payload.pasteboardType.rawValue,
                payloadEncryptedData <- encryptedPayload,
                payloadByteSize <- payload.byteSize,
                payloadPreview <- nil,
                payloadRank <- payload.rank
            ),
            contentType: payload.contentType,
            pasteboardType: payload.pasteboardType.rawValue
        )
    }

    private func clipboardPayload(from row: Row) -> ClipboardPayload? {
        guard let decrypted = security.decrypt(
            row[payloadEncryptedData],
            context: .payloadData(itemID: row[payloadItemID], payloadID: row[payloadID])
        ) else {
            return nil
        }
        guard let data = Data(base64Encoded: decrypted) else {
            return nil
        }
        let contentType = ClipboardContentType(rawValue: row[payloadContentType]) ?? .unknown
        return ClipboardPayload(
            id: row[payloadID],
            contentType: contentType,
            pasteboardType: NSPasteboard.PasteboardType(rawValue: row[payloadPasteboardType]),
            data: data,
            preview: row[payloadPreview],
            rank: row[payloadRank]
        )
    }

    private func encryptedBase64PayloadData(for data: Data, itemID: UUID, payloadID: UUID) -> String? {
        security.encrypt(
            data.base64EncodedString(),
            context: .payloadData(itemID: itemID, payloadID: payloadID)
        )
    }

    private func applyRetentionPolicy(in db: Connection) throws {
        if let maxAgeDays = retentionPolicy.maxAgeDays,
           let cutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: Date()) {
            let oldIDs = try db.prepare(items.filter(timestamp < cutoff && isFavorite == false)).map { $0[id] }
            for itemID in oldIDs {
                try deleteItemRows(withID: itemID, in: db)
            }
        }

        if let maxStoredItems = retentionPolicy.maxStoredItems {
            let itemIDs = try db.prepare(items.filter(isFavorite == false).order(timestamp.desc)).map { $0[id] }
            let idsToDelete = Array(itemIDs.dropFirst(maxStoredItems))
            for itemID in idsToDelete {
                try deleteItemRows(withID: itemID, in: db)
            }
        }
    }

    private func deleteItemRows(withID itemID: UUID, in db: Connection) throws {
        try db.run(payloads.filter(payloadItemID == itemID).delete())
        try db.run(itemFolders.filter(itemFolderItemID == itemID).delete())
        try db.run(items.filter(id == itemID).delete())
    }
}
