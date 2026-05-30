import Foundation

enum AppInfo {
    static let displayName = "Forkclip"
    static let shortDescription = "メニューバーから素早く使える、ローカル保存のクリップボード履歴ツールです。"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "10"
    }

    static var versionDisplay: String {
        "Version \(version) (\(build))"
    }
}

enum DocumentationLocator {
    private static let bundledUserDocsDirectoryName = "ForkclipUserDocs"

    static func userDocsDirectory() -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let userDocsURL = resourceURL.appendingPathComponent(bundledUserDocsDirectoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: userDocsURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return userDocsURL
    }
}
