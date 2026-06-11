import SwiftUI
import AppKit

struct ClipboardItem: Identifiable, Codable, Sendable {
    let id: UUID
    let content: String
    let timestamp: Date
    var displayTitle: String? = nil
    var bundleID: String? = nil
    var isSecret: Bool = false
    var isFavorite: Bool = false
    var usageCount: Int = 0
    var lastUsedAt: Date? = nil
    var captureCount: Int = 1
    var lastCapturedAt: Date
    var primaryContentType: ClipboardContentType = .plainText

    enum CodingKeys: String, CodingKey {
        case id
        case content
        case timestamp
        case displayTitle
        case bundleID
        case isSecret
        case isFavorite
        case usageCount
        case lastUsedAt
        case captureCount
        case lastCapturedAt
        case primaryContentType
    }

    init(
        id: UUID,
        content: String,
        timestamp: Date,
        displayTitle: String? = nil,
        bundleID: String? = nil,
        isSecret: Bool = false,
        isFavorite: Bool = false,
        usageCount: Int = 0,
        lastUsedAt: Date? = nil,
        captureCount: Int = 1,
        lastCapturedAt: Date? = nil,
        primaryContentType: ClipboardContentType = .plainText
    ) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.displayTitle = Self.normalizedDisplayTitle(displayTitle)
        self.bundleID = bundleID
        self.isSecret = isSecret
        self.isFavorite = isFavorite
        self.usageCount = max(0, usageCount)
        self.lastUsedAt = lastUsedAt
        self.captureCount = max(1, captureCount)
        self.lastCapturedAt = lastCapturedAt ?? timestamp
        self.primaryContentType = primaryContentType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        displayTitle = Self.normalizedDisplayTitle(try container.decodeIfPresent(String.self, forKey: .displayTitle))
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        isSecret = try container.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        usageCount = max(0, try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        captureCount = max(1, try container.decodeIfPresent(Int.self, forKey: .captureCount) ?? 1)
        lastCapturedAt = try container.decodeIfPresent(Date.self, forKey: .lastCapturedAt) ?? timestamp
        primaryContentType = try container.decodeIfPresent(ClipboardContentType.self, forKey: .primaryContentType) ?? .plainText
    }

    static func normalizedDisplayTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

enum ClipboardContentType: String, Codable, Sendable {
    case plainText
    case urlText
    case fileURL
    case rtf
    case html
    case image
    case unknown
}

enum ClipboardPersistenceError: LocalizedError, Equatable, Sendable {
    case databaseUnavailable
    case itemEncryptionFailed(SecurityManager.SecurityError?)
    case displayTitleEncryptionFailed(SecurityManager.SecurityError?)
    case payloadEncryptionFailed(contentType: ClipboardContentType, pasteboardType: String, securityError: SecurityManager.SecurityError?)
    case itemWriteFailed(String)
    case payloadWriteFailed(contentType: ClipboardContentType, pasteboardType: String, underlying: String)
    case retentionPolicyFailed(String)
    case databaseWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "DB を利用できません。"
        case .itemEncryptionFailed(let securityError):
            return securityError?.localizedDescription ?? "履歴本文の暗号化に失敗しました。"
        case .displayTitleEncryptionFailed(let securityError):
            return securityError?.localizedDescription ?? "表示名の暗号化に失敗しました。"
        case .payloadEncryptionFailed(let contentType, let pasteboardType, let securityError):
            let baseMessage = securityError?.localizedDescription ?? "ペイロードの暗号化に失敗しました。"
            return "\(baseMessage) (\(contentType.rawValue)/\(pasteboardType))"
        case .itemWriteFailed(let underlying):
            return "履歴行の保存に失敗しました。\(underlying)"
        case .payloadWriteFailed(let contentType, let pasteboardType, let underlying):
            return "ペイロードの保存に失敗しました。(\(contentType.rawValue)/\(pasteboardType)) \(underlying)"
        case .retentionPolicyFailed(let underlying):
            return "保存後の保持ポリシー適用に失敗しました。\(underlying)"
        case .databaseWriteFailed(let underlying):
            return "DB 書き込みに失敗しました。\(underlying)"
        }
    }
}

protocol ClipboardStore: AnyObject, Sendable {
    var lastFetchFailureCount: Int { get async }
    func saveItem(_ item: ClipboardItem, originBundleID: String?, secret: Bool, migrated: Bool) async throws
    func saveItem(_ item: ClipboardItem, payloads: [ClipboardPayload], originBundleID: String?, secret: Bool, migrated: Bool) async throws
    func payloads(for itemID: UUID) async -> [ClipboardPayload]
    func deleteItem(withID itemID: UUID) async
    func fetchAll() async -> [ClipboardItem]
    func fetchFolders() async -> [ClipboardFolder]
    func fetchFolderAssignments() async -> [UUID: Set<UUID>]
    func createFolder(named name: String, color: String) async -> ClipboardFolder?
    func updateFolder(_ folder: ClipboardFolder) async -> Bool
    func deleteFolder(withID id: UUID) async
    func assignItem(_ itemID: UUID, toFolder folderID: UUID) async -> Bool
    func unassignItem(_ itemID: UUID, fromFolder folderID: UUID) async
    func unassignItemFromAllFolders(_ itemID: UUID) async
    func reorderFolders(_ orderedFolders: [ClipboardFolder]) async -> Bool
    func updateFavoriteState(for itemID: UUID, isFavorite: Bool) async -> Bool
    func updateSecretState(for itemID: UUID, isSecret: Bool) async -> Bool
    func updateDisplayTitle(for itemID: UUID, displayTitle: String?) async -> Bool
    func recordDuplicateCapture(content: String, primaryContentType: ClipboardContentType, bundleID: String?, at date: Date) async -> ClipboardItem?
    func recordUse(for itemID: UUID, at date: Date) async -> ClipboardItem?
    func diagnosticsSnapshot() async -> DiagnosticsSnapshot
    func recoverFromMissingKey() async -> Bool
}

extension ClipboardStore {
    func saveItem(_ item: ClipboardItem, payloads: [ClipboardPayload], originBundleID: String?, secret: Bool, migrated: Bool) async throws {
        try await saveItem(item, originBundleID: originBundleID, secret: secret, migrated: migrated)
    }

    func payloads(for itemID: UUID) async -> [ClipboardPayload] {
        []
    }

    func recordDuplicateCapture(content: String, primaryContentType: ClipboardContentType, bundleID: String?, at date: Date) async -> ClipboardItem? {
        nil
    }
}

@MainActor
protocol SecurityProviding: AnyObject {
    var lastError: SecurityManager.SecurityError? { get }
    func isApplicationBlacklisted(_ bundleID: String?) -> Bool
    func isLikelySecret(_ text: String) -> Bool
    func resetLastError()
    func currentKeyState() -> SecurityKeyState
    func ensureEncryptionKeyExists() -> Bool
}

extension DatabaseManager: ClipboardStore {}
@MainActor extension SecurityManager: SecurityProviding {}

enum ClipboardFeedbackEvent: Equatable {
    case externalCaptureSaved
    case appCopySucceeded
}

@MainActor
class ClipboardManager: ObservableObject {
    let historyState: ClipboardHistoryState
    let folderState = ClipboardFolderState()
    let selectionState = ClipboardSelectionState()
    let diagnosticsState = ClipboardDiagnosticsState()

    private let pasteboard: PasteboardProviding
    private let store: ClipboardStore
    private let security: SecurityProviding
    private let frontmostApplicationProvider: FrontmostApplicationProviding
    private let autoPasteCoordinator: AutoPasteCoordinating
    private let monitorScheduler: ClipboardMonitorScheduling
    private lazy var monitor = ClipboardMonitor(pasteboard: pasteboard, scheduler: monitorScheduler) { [weak self] changeCount in
        self?.handleClipboardChange(changeCount: changeCount)
    }
    private var ignoredChangeCount: Int?
    private var lastProcessedChangeDate: Date?
    private var lastSaveStatus: ClipboardOperationStatus = .notRun
    private var lastSaveError: String?
    private var payloadCache: [UUID: [ClipboardPayload]] = [:]
    private var imageThumbnailCache: [UUID: NSImage] = [:]
    private var imageThumbnailMisses: Set<UUID> = []
    private var autoPasteTarget: AutoPasteTarget?
    private var initialLoadTask: Task<Void, Never>?
    private var pendingClipboardTask: Task<Void, Never>?

    var feedbackHandler: ((ClipboardFeedbackEvent) -> Void)?

    var items: [ClipboardItem] {
        get { historyState.items }
        set { historyState.items = newValue }
    }

    var queue: [ClipboardItem] {
        get { historyState.queue }
        set { historyState.queue = newValue }
    }

    var isQueueMode: Bool {
        get { historyState.isQueueMode }
        set { historyState.isQueueMode = newValue }
    }

    var isPrivateMode: Bool {
        get { historyState.isPrivateMode }
        set { historyState.isPrivateMode = newValue }
    }

    var searchQuery: String {
        get { historyState.searchQuery }
        set { historyState.searchQuery = newValue }
    }

    var sourceAppFilter: String {
        get { historyState.sourceAppFilter }
        set { historyState.sourceAppFilter = newValue }
    }

    var folders: [ClipboardFolder] {
        get { folderState.folders }
        set { folderState.folders = newValue }
    }

    var selectedFolder: HistoryFolderSelection {
        get { folderState.selectedFolder }
        set { folderState.selectedFolder = newValue }
    }

    var isFavoritesOnly: Bool {
        get { historyState.isFavoritesOnly }
        set { historyState.isFavoritesOnly = newValue }
    }

    var selectedItemIDs: Set<UUID> {
        get { selectionState.selectedItemIDs }
        set { selectionState.selectedItemIDs = newValue }
    }

    var bannerStatus: ClipboardBannerStatus? {
        get { diagnosticsState.bannerStatus }
        set { diagnosticsState.bannerStatus = newValue }
    }

    var diagnostics: DiagnosticsSnapshot {
        get { diagnosticsState.diagnostics }
        set { diagnosticsState.diagnostics = newValue }
    }

    var isDiagnosticsPanelVisible: Bool {
        get { diagnosticsState.isDiagnosticsPanelVisible }
        set { diagnosticsState.isDiagnosticsPanelVisible = newValue }
    }

    var recoveryStatus: ClipboardRecoveryStatus? {
        get { diagnosticsState.recoveryStatus }
        set { diagnosticsState.recoveryStatus = newValue }
    }

    var folderStatus: ClipboardFolderStatus? {
        get { diagnosticsState.folderStatus }
        set { diagnosticsState.folderStatus = newValue }
    }

    var sourceBundleIDs: [String] {
        Array(Set(items.compactMap(\.bundleID))).sorted {
            sourceAppDisplayName(for: $0) < sourceAppDisplayName(for: $1)
        }
    }

    var visibleItems: [ClipboardItem] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let matchesSource = sourceAppFilter.isEmpty || item.bundleID == sourceAppFilter
            let matchesQuery = query.isEmpty
                || item.content.localizedCaseInsensitiveContains(query)
                || item.bundleID?.localizedCaseInsensitiveContains(query) == true
            let matchesFolder = itemMatchesSelectedFolder(item)
            let matchesFavorite = !isFavoritesOnly || item.isFavorite
            return matchesSource && matchesQuery && matchesFolder && matchesFavorite
        }
    }

    func sourceAppDisplayName(for bundleID: String) -> String {
        bundleID.components(separatedBy: ".").last?.uppercased() ?? bundleID
    }

    func folderName(for selection: HistoryFolderSelection) -> String {
        folderState.folderName(for: selection)
    }

    func folderIDs(for item: ClipboardItem) -> Set<UUID> {
        folderState.folderIDs(for: item)
    }

    func imageThumbnail(for item: ClipboardItem) -> NSImage? {
        guard item.primaryContentType == .image, !item.isSecret else {
            return nil
        }
        if let cachedThumbnail = imageThumbnailCache[item.id] {
            return cachedThumbnail
        }
        guard !imageThumbnailMisses.contains(item.id),
              let imagePayload = payloadCache[item.id]?.first(where: { $0.contentType == .image }),
              let thumbnail = NSImage(data: imagePayload.data) else {
            imageThumbnailMisses.insert(item.id)
            return nil
        }
        imageThumbnailCache[item.id] = thumbnail
        return thumbnail
    }

    private func itemMatchesSelectedFolder(_ item: ClipboardItem) -> Bool {
        switch selectedFolder {
        case .all:
            return true
        case .unfiled:
            return folderIDs(for: item).isEmpty
        case .folder(let folderID):
            return folderIDs(for: item).contains(folderID)
        }
    }

    init(
        pasteboard: PasteboardProviding,
        store: ClipboardStore,
        security: SecurityProviding,
        frontmostApplicationProvider: FrontmostApplicationProviding,
        initialPrivateMode: Bool,
        autoPasteCoordinator: AutoPasteCoordinating = WorkspaceAutoPasteCoordinator(),
        monitorScheduler: ClipboardMonitorScheduling = RunLoopClipboardMonitorScheduler()
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.security = security
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.autoPasteCoordinator = autoPasteCoordinator
        self.monitorScheduler = monitorScheduler
        self.historyState = ClipboardHistoryState(isPrivateMode: initialPrivateMode)

        initialLoadTask = Task { @MainActor [weak self] in
            await self?.loadInitialState()
        }
    }

    func startMonitoring() {
        monitor.start()
        Task { @MainActor [weak self] in
            await self?.refreshDiagnostics()
            self?.updateStatusMessage()
        }
    }

    func stopMonitoring() {
        monitor.stop()
        Task { @MainActor [weak self] in
            await self?.refreshDiagnostics()
            self?.updateStatusMessage()
        }
    }

    func captureAutoPasteTarget() {
        autoPasteTarget = autoPasteCoordinator.captureTarget()
    }

    func pollClipboardForTests() async {
        monitor.pollPasteboard()
        await pendingClipboardTask?.value
        await refreshDiagnostics()
    }

    func waitForClipboardProcessingForTests() async {
        await pendingClipboardTask?.value
        await refreshDiagnostics()
    }

    func refreshFolders() async {
        await loadFolders()
    }

    func handleClipboardChange(changeCount: Int) {
        lastProcessedChangeDate = Date()
        pendingClipboardTask = Task { @MainActor [weak self] in
            await self?.handleNewClipboardItem(changeCount: changeCount)
        }
    }

    func handleNewClipboardItem(changeCount: Int? = nil) async {
        let currentChangeCount = changeCount ?? pasteboard.changeCount
        if ignoredChangeCount == currentChangeCount {
            ignoredChangeCount = nil
            lastSaveStatus = .selfCopyIgnored
            lastSaveError = nil
            await refreshDiagnostics()
            return
        }
        if isPrivateMode {
            lastSaveStatus = .privateModeSkipped
            lastSaveError = nil
            await refreshDiagnostics()
            updateStatusMessage()
            return
        }

        let bundleID = frontmostApplicationProvider.frontmostBundleIdentifier()

        if security.isApplicationBlacklisted(bundleID) {
            lastSaveStatus = .blacklistedApplicationIgnored
            lastSaveError = bundleID
            AppLogger.app.debug("Ignored clipboard item from blacklisted app \(bundleID ?? "unknown", privacy: .public)")
            await refreshDiagnostics()
            return
        }

        let metadata = ClipboardPasteboardMetadata.read(from: pasteboard)
        if metadata.hasConcealedContent {
            lastSaveStatus = .concealedContentSkipped
            lastSaveError = metadata.concealedTypeNames.joined(separator: ",")
            AppLogger.app.debug("Ignored concealed clipboard item: \(self.lastSaveError ?? "unknown", privacy: .public)")
            await refreshDiagnostics()
            updateStatusMessage()
            return
        }

        let capture = ClipboardCaptureSnapshot.read(from: pasteboard, metadata: metadata)

        if !capture.unsupportedTypeNames.isEmpty {
            AppLogger.app.debug("Unsupported pasteboard types ignored: \(capture.unsupportedTypeNames.joined(separator: ","), privacy: .public)")
        }

        guard capture.hasSupportedContent,
              let previewText = capture.previewText,
              !previewText.isEmpty else {
            if capture.hasNonTextContent {
                lastSaveStatus = .unsupportedContentSkipped
                lastSaveError = captureDiagnosticsDescription(capture)
                AppLogger.app.debug("Ignored unsupported clipboard change: \(self.lastSaveError ?? "unknown", privacy: .public)")
            } else {
                lastSaveStatus = .emptyStringIgnored
                lastSaveError = nil
            }
            await refreshDiagnostics()
            updateStatusMessage()
            return
        }
        let captureDate = Date()
        let isSecret = capture.plainText.map(security.isLikelySecret) ?? false
        if capture.isPlainTextOnly,
           var updatedItem = await store.recordDuplicateCapture(
                content: previewText,
                primaryContentType: capture.primaryContentType,
                bundleID: bundleID,
                at: captureDate
           ) {
            if updatedItem.isSecret != isSecret,
               await store.updateSecretState(for: updatedItem.id, isSecret: isSecret) {
                updatedItem.isSecret = isSecret
            }
            lastSaveStatus = .duplicateRecorded
            lastSaveError = nil
            payloadCache[updatedItem.id] = capture.payloads
            await loadHistory()
            return
        }

        let newItem = ClipboardItem(
            id: UUID(),
            content: previewText,
            timestamp: captureDate,
            bundleID: bundleID,
            isSecret: isSecret,
            primaryContentType: capture.primaryContentType
        )

        AppLogger.app.debug("Attempting to persist clipboard change \(currentChangeCount, privacy: .public)")
        do {
            try await store.saveItem(newItem, payloads: capture.payloads, originBundleID: bundleID, secret: isSecret, migrated: false)
        } catch let error as ClipboardPersistenceError {
            lastSaveStatus = .saveFailed
            lastSaveError = error.localizedDescription
            await refreshDiagnostics()
            updateStatusMessage()
            return
        } catch {
            lastSaveStatus = .saveFailed
            lastSaveError = String(describing: error)
            await refreshDiagnostics()
            updateStatusMessage()
            return
        }

        lastSaveStatus = .saveSucceeded
        lastSaveError = nil
        payloadCache[newItem.id] = capture.payloads
        await loadHistory()
        feedbackHandler?(.externalCaptureSaved)
    }

    private func captureDiagnosticsDescription(_ capture: ClipboardCaptureSnapshot) -> String {
        let supported = capture.contentTypes.map(\.rawValue)
        let unsupported = capture.unsupportedTypeNames
        return (supported + unsupported).joined(separator: ",")
    }

    private func loadInitialState() async {
        await loadHistory()
        await loadFolders()
        await runStartupSelfCheck()
    }

    func waitForInitialLoadForTests() async {
        await initialLoadTask?.value
    }

    private func loadHistory() async {
        let fetchedItems = await store.fetchAll()
        await applyFetchedHistory(fetchedItems)
    }

    func reclassifySecretStateForCurrentRules() async {
        var fetchedItems = await store.fetchAll()
        await reclassifySecretStateIfNeeded(for: &fetchedItems)
        await applyFetchedHistory(fetchedItems)
    }

    private func applyFetchedHistory(_ fetchedItems: [ClipboardItem]) async {
        var fetchedPayloads: [UUID: [ClipboardPayload]] = [:]
        for item in fetchedItems {
            fetchedPayloads[item.id] = await store.payloads(for: item.id)
        }
        payloadCache = fetchedPayloads
        self.items = fetchedItems
        pruneImageThumbnailCache()
        await refreshDiagnostics()
        updateStatusMessage()
    }

    private func reclassifySecretStateIfNeeded(for fetchedItems: inout [ClipboardItem]) async {
        for index in fetchedItems.indices {
            let updatedSecretState = security.isLikelySecret(fetchedItems[index].content)
            guard updatedSecretState != fetchedItems[index].isSecret else { continue }
            guard await store.updateSecretState(for: fetchedItems[index].id, isSecret: updatedSecretState) else {
                continue
            }
            fetchedItems[index].isSecret = updatedSecretState
        }
    }

    private func loadFolders() async {
        folders = await store.fetchFolders()
        folderState.itemFolderIDs = await store.fetchFolderAssignments()
        if case .folder(let folderID) = selectedFolder,
           !folders.contains(where: { $0.id == folderID }) {
            selectedFolder = .all
        }
    }

    private func runStartupSelfCheck() async {
        let keyReady = security.ensureEncryptionKeyExists()
        if !keyReady {
            AppLogger.security.error("Startup self-check failed to ensure encryption key.")
            lastSaveStatus = .startupSelfCheckFailed
            lastSaveError = security.lastError?.localizedDescription
        }
        await refreshDiagnostics()
        updateStatusMessage()
    }

    private func updateStatusMessage() {
        if monitor.state != .monitoring {
            bannerStatus = .monitorNotRunning
            return
        }

        if lastSaveStatus == .saveFailed {
            bannerStatus = .saveFailed(detail: lastSaveError)
            return
        }

        if diagnostics.keyState == .missing || diagnostics.keyState == .failed {
            bannerStatus = .keyProblem(detail: diagnostics.securityErrorDescription)
            return
        }

        if diagnostics.fetchFailureCount > 0 {
            bannerStatus = .fetchFailures(count: diagnostics.fetchFailureCount, detail: security.lastError?.localizedDescription)
            return
        }

        if items.isEmpty {
            bannerStatus = .waitingForData
            return
        }

        bannerStatus = nil
        security.resetLastError()
    }

    // --- Formatting & Queue ---
    func getPlainText(from content: String) -> String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func addToQueue(_ item: ClipboardItem) {
        if !queue.contains(where: { $0.id == item.id }) {
            queue.append(item)
        }
    }

    func popFromQueue() -> ClipboardItem? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    func copyToClipboard(_ item: ClipboardItem, autoPaste: Bool = false) async {
        pasteboard.clearContents()
        let payloads = await payloadsForItem(item.id)
        let didCopy = writeToPasteboard(payloads: payloads, fallbackContent: item.content)
        if didCopy {
            ignoredChangeCount = pasteboard.changeCount
            await recordUse(for: item)
            feedbackHandler?(.appCopySucceeded)
        }
        if isQueueMode {
            // queue mode retains items for sequential manual pasting.
        }
        NSApp.hide(nil)
        guard autoPaste, didCopy else {
            autoPasteTarget = nil
            return
        }
        await pasteToCapturedTarget()
    }

    func copyPlainTextToClipboard(from item: ClipboardItem) async {
        let plainText = getPlainText(from: item.content)
        pasteboard.clearContents()
        let didCopy = writeToPasteboard(payloads: [.plainText(plainText)], fallbackContent: plainText)
        if didCopy {
            ignoredChangeCount = pasteboard.changeCount
            await recordUse(for: item)
            feedbackHandler?(.appCopySucceeded)
        }
        NSApp.hide(nil)
    }

    private func payloadsForItem(_ itemID: UUID) async -> [ClipboardPayload] {
        if let cachedPayloads = payloadCache[itemID] {
            return cachedPayloads
        }
        let payloads = await store.payloads(for: itemID)
        payloadCache[itemID] = payloads
        return payloads
    }

    private func recordUse(for item: ClipboardItem) async {
        guard let updatedItem = await store.recordUse(for: item.id, at: Date()) else { return }
        updateUsageState(with: updatedItem)
    }

    private func updateUsageState(with updatedItem: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
            items[index].usageCount = updatedItem.usageCount
            items[index].lastUsedAt = updatedItem.lastUsedAt
        }
        if let index = queue.firstIndex(where: { $0.id == updatedItem.id }) {
            queue[index].usageCount = updatedItem.usageCount
            queue[index].lastUsedAt = updatedItem.lastUsedAt
        }
    }

    private func writeToPasteboard(payloads: [ClipboardPayload], fallbackContent: String) -> Bool {
        let payloadsToWrite = payloads.isEmpty ? [.plainText(fallbackContent)] : payloads.sorted {
            if $0.rank == $1.rank {
                return $0.contentType.rawValue < $1.contentType.rawValue
            }
            return $0.rank < $1.rank
        }

        var didWrite = false
        for payload in payloadsToWrite {
            didWrite = writePayload(payload) || didWrite
        }
        return didWrite
    }

    private func writePayload(_ payload: ClipboardPayload) -> Bool {
        switch payload.contentType {
        case .plainText:
            guard let text = String(data: payload.data, encoding: .utf8) else { return false }
            return pasteboard.setString(text, forType: .string)
        case .urlText:
            guard let text = String(data: payload.data, encoding: .utf8) else { return false }
            let wroteURL = pasteboard.setString(text, forType: .URL)
            let wroteString = pasteboard.setString(text, forType: .string)
            return wroteURL || wroteString
        case .fileURL:
            guard let text = String(data: payload.data, encoding: .utf8) else {
                return pasteboard.setData(payload.data, forType: .fileURL)
            }
            return pasteboard.setString(text, forType: .fileURL)
        case .rtf, .html, .image:
            return pasteboard.setData(payload.data, forType: payload.pasteboardType)
        case .unknown:
            return false
        }
    }

    private func pasteToCapturedTarget() async {
        guard let target = autoPasteTarget else {
            bannerStatus = .autoPasteFailed(target: nil)
            return
        }
        autoPasteTarget = nil
        guard await autoPasteCoordinator.paste(to: target) else {
            bannerStatus = .autoPasteFailed(target: target.displayName)
            return
        }
        bannerStatus = nil
    }

    func delete(_ item: ClipboardItem) async {
        items.removeAll { $0.id == item.id }
        folderState.itemFolderIDs.removeValue(forKey: item.id)
        payloadCache.removeValue(forKey: item.id)
        selectedItemIDs.remove(item.id)
        imageThumbnailCache.removeValue(forKey: item.id)
        imageThumbnailMisses.remove(item.id)
        await store.deleteItem(withID: item.id)
        await refreshDiagnostics()
        updateStatusMessage()
    }

    private func pruneImageThumbnailCache() {
        let itemIDs = Set(items.map(\.id))
        imageThumbnailCache = imageThumbnailCache.filter { itemIDs.contains($0.key) }
        imageThumbnailMisses.formIntersection(itemIDs)
    }

    @discardableResult
    func createFolder(named name: String) async -> Bool {
        guard let folder = await store.createFolder(named: name, color: "#4A90E2") else {
            folderStatus = .emptyName
            return false
        }
        folders.append(folder)
        folders.sort { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
        selectedFolder = .folder(folder.id)
        folderStatus = nil
        return true
    }

    @discardableResult
    func renameFolder(_ folder: ClipboardFolder, to name: String) async -> Bool {
        var updated = folder
        updated.name = name
        guard await store.updateFolder(updated) else {
            folderStatus = .updateFailed
            return false
        }
        await loadFolders()
        folderStatus = nil
        return true
    }

    func deleteFolder(_ folder: ClipboardFolder) async {
        await store.deleteFolder(withID: folder.id)
        if selectedFolder == .folder(folder.id) {
            selectedFolder = .all
        }
        await loadFolders()
        folderStatus = nil
    }

    func assign(_ item: ClipboardItem, to folder: ClipboardFolder) async {
        guard await store.assignItem(item.id, toFolder: folder.id) else {
            folderStatus = .assignFailed
            return
        }
        folderState.itemFolderIDs[item.id, default: []].insert(folder.id)
        folderStatus = nil
    }

    func unassign(_ item: ClipboardItem, from folder: ClipboardFolder) async {
        await store.unassignItem(item.id, fromFolder: folder.id)
        folderState.itemFolderIDs[item.id]?.remove(folder.id)
        if folderState.itemFolderIDs[item.id]?.isEmpty == true {
            folderState.itemFolderIDs.removeValue(forKey: item.id)
        }
        folderStatus = nil
    }

    func unassignFromAllFolders(_ item: ClipboardItem) async {
        await store.unassignItemFromAllFolders(item.id)
        folderState.itemFolderIDs.removeValue(forKey: item.id)
        folderStatus = nil
    }

    func toggleFavorite(for item: ClipboardItem) async {
        let newValue = !item.isFavorite
        guard await store.updateFavoriteState(for: item.id, isFavorite: newValue) else {
            folderStatus = .favoriteUpdateFailed
            return
        }

        updateFavoriteState(for: item.id, isFavorite: newValue)
        folderStatus = nil
    }

    @discardableResult
    func updateDisplayTitle(for item: ClipboardItem, title: String?) async -> Bool {
        let normalizedTitle = ClipboardItem.normalizedDisplayTitle(title)
        guard await store.updateDisplayTitle(for: item.id, displayTitle: normalizedTitle) else {
            folderStatus = .displayTitleUpdateFailed
            return false
        }

        updateDisplayTitleState(for: item.id, displayTitle: normalizedTitle)
        folderStatus = nil
        return true
    }

    private func updateFavoriteState(for itemID: UUID, isFavorite: Bool) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].isFavorite = isFavorite
        }
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            queue[index].isFavorite = isFavorite
        }
    }

    private func updateDisplayTitleState(for itemID: UUID, displayTitle: String?) {
        if let index = items.firstIndex(where: { $0.id == itemID }) {
            items[index].displayTitle = displayTitle
        }
        if let index = queue.firstIndex(where: { $0.id == itemID }) {
            queue[index].displayTitle = displayTitle
        }
    }

    func moveFolder(_ folder: ClipboardFolder, direction: Int) async {
        guard let currentIndex = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        let targetIndex = currentIndex + direction
        guard folders.indices.contains(targetIndex) else { return }
        folders.swapAt(currentIndex, targetIndex)
        folders = folders.enumerated().map { index, folder in
            ClipboardFolder(
                id: folder.id,
                name: folder.name,
                color: folder.color,
                sortOrder: index,
                createdAt: folder.createdAt,
                updatedAt: Date()
            )
        }
        _ = await store.reorderFolders(folders)
        folderStatus = nil
    }

    func isSelected(_ item: ClipboardItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func toggleSelection(for item: ClipboardItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }

    func clearSelection() {
        selectedItemIDs.removeAll()
    }

    func assignSelectedItems(to folder: ClipboardFolder) async {
        for itemID in selectedItemIDs {
            if await store.assignItem(itemID, toFolder: folder.id) {
                folderState.itemFolderIDs[itemID, default: []].insert(folder.id)
            }
        }
        folderStatus = nil
    }

    func unassignSelectedItemsFromAllFolders() async {
        for itemID in selectedItemIDs {
            await store.unassignItemFromAllFolders(itemID)
            folderState.itemFolderIDs.removeValue(forKey: itemID)
        }
        folderStatus = nil
    }

    func deleteSelectedItems() async {
        let idsToDelete = selectedItemIDs
        for itemID in idsToDelete {
            await store.deleteItem(withID: itemID)
            folderState.itemFolderIDs.removeValue(forKey: itemID)
            payloadCache.removeValue(forKey: itemID)
        }
        items.removeAll { idsToDelete.contains($0.id) }
        selectedItemIDs.removeAll()
        await refreshDiagnostics()
        updateStatusMessage()
    }

    func refreshDiagnostics() async {
        var snapshot = await store.diagnosticsSnapshot()
        snapshot.monitorState = monitor.state
        snapshot.lastObservedChangeCount = monitor.lastObservedChangeCount
        snapshot.lastProcessedChangeAt = lastProcessedChangeDate
        snapshot.lastSaveStatus = lastSaveStatus
        snapshot.lastSaveError = lastSaveError
        diagnostics = snapshot
    }

    func recoverFromMissingKey() async {
        let didRecover = await store.recoverFromMissingKey()
        if didRecover {
            recoveryStatus = .succeeded
            AppLogger.security.notice("Key recovery flow completed successfully.")
            lastSaveStatus = .recoverySucceeded
            lastSaveError = nil
        } else {
            recoveryStatus = .failed
            AppLogger.security.error("Key recovery flow failed.")
            lastSaveStatus = .recoveryFailed
            lastSaveError = security.lastError?.localizedDescription
        }
        await loadHistory()
    }
}
