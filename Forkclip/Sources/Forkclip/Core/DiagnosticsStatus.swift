import Foundation

enum DatabaseStatus: Equatable, Sendable {
    case uninitialized
    case available
    case failed
}

enum SecurityKeyState: Equatable, Sendable {
    case unchecked
    case available
    case missing
    case failed
}

enum ClipboardOperationStatus: Equatable, Sendable {
    case notRun
    case saveSucceeded
    case selfCopyIgnored
    case privateModeSkipped
    case blacklistedApplicationIgnored
    case sourceApplicationUnknownSkipped
    case concealedContentSkipped
    case resourceLimitSkipped
    case unsupportedContentSkipped
    case emptyStringIgnored
    case duplicateIgnored
    case duplicateRecorded
    case saveFailed
    case startupSelfCheckFailed
    case recoverySucceeded
    case recoveryFailed
}

enum ClipboardBannerStatus: Equatable, Sendable {
    case monitorNotRunning
    case saveFailed(detail: String?)
    case keyProblem(detail: String?)
    case fetchFailures(count: Int, detail: String?)
    case autoPasteFailed(target: String?)
    case waitingForData
}

enum ClipboardRecoveryStatus: Equatable, Sendable {
    case succeeded
    case failed
}

enum ClipboardFolderStatus: Equatable, Sendable {
    case emptyName
    case updateFailed
    case assignFailed
    case favoriteUpdateFailed
    case displayTitleUpdateFailed
}
