import Foundation

enum AppPaths {
    private static let appDirectoryName = "Forkclip"
    private static let databaseFileName = "forkclip.sqlite"
    private static let backupsDirectoryName = "Backups"
    static let ownerOnlyDirectoryPermissions = 0o700
    static let ownerOnlyFilePermissions = 0o600

    /// アプリの永続データを保存する Application Support 配下のディレクトリを返す。
    static func applicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default
            .url(for: .applicationSupportDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: true)
        let directoryURL = baseURL.appendingPathComponent(appDirectoryName, isDirectory: true)
        try createOwnerOnlyDirectory(at: directoryURL)
        return directoryURL
    }

    /// 現行の SQLite 保存先。
    static func databaseURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent(databaseFileName)
    }

    static func backupsDirectory() throws -> URL {
        let directoryURL = try applicationSupportDirectory().appendingPathComponent(backupsDirectoryName, isDirectory: true)
        try createOwnerOnlyDirectory(at: directoryURL)
        return directoryURL
    }

    static func blacklistURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("blacklist_bundle_ids.txt")
    }

    static func customSecretPatternsURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("custom_secret_patterns.json")
    }

    static func retentionPolicyURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("retention_policy.json")
    }

    static func appSettingsURL() throws -> URL {
        try applicationSupportDirectory().appendingPathComponent("app_settings.json")
    }

    static func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func createOwnerOnlyDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: ownerOnlyDirectoryAttributes
        )
        try applyOwnerOnlyDirectoryPermissions(to: url)
    }

    static func applyOwnerOnlyDirectoryPermissions(to url: URL) throws {
        try FileManager.default.setAttributes(ownerOnlyDirectoryAttributes, ofItemAtPath: url.path)
    }

    static func applyOwnerOnlyFilePermissions(to url: URL) throws {
        try FileManager.default.setAttributes(ownerOnlyFileAttributes, ofItemAtPath: url.path)
    }

    private static var ownerOnlyDirectoryAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: NSNumber(value: ownerOnlyDirectoryPermissions)]
    }

    private static var ownerOnlyFileAttributes: [FileAttributeKey: Any] {
        [.posixPermissions: NSNumber(value: ownerOnlyFilePermissions)]
    }
}
