import Foundation
import Security
import CryptoKit
import Darwin
import LocalAuthentication

struct EncryptionContext: Equatable, Sendable {
    private let components: [String]

    private init(_ components: [String]) {
        self.components = components
    }

    var authenticatedData: Data {
        Data(components.joined(separator: "\u{1f}").utf8)
    }

    static func itemContent(itemID: UUID) -> EncryptionContext {
        EncryptionContext([
            "forkclip",
            "v1",
            "clipboard_items",
            itemID.uuidString.lowercased(),
            "content"
        ])
    }

    static func itemDisplayTitle(itemID: UUID) -> EncryptionContext {
        EncryptionContext([
            "forkclip",
            "v1",
            "clipboard_items",
            itemID.uuidString.lowercased(),
            "display_title"
        ])
    }

    static func payloadData(itemID: UUID, payloadID: UUID) -> EncryptionContext {
        EncryptionContext([
            "forkclip",
            "v1",
            "clipboard_payloads",
            itemID.uuidString.lowercased(),
            payloadID.uuidString.lowercased(),
            "encrypted_data"
        ])
    }
}

protocol ClipboardCryptographyProviding: AnyObject, Sendable {
    var lastError: SecurityManager.SecurityError? { get }
    func encrypt(_ text: String, context: EncryptionContext?) -> String?
    func decrypt(_ base64Encoded: String, context: EncryptionContext?) -> String?
    func currentKeyState() -> SecurityKeyState
    func replaceMissingKey() -> Bool
}

extension SecurityManager: ClipboardCryptographyProviding {}

final class SecurityManager: @unchecked Sendable {
    protocol KeyStorage: AnyObject, Sendable {
        func saveKeyData(_ data: Data, service: String, account: String, accessibility: CFString) throws
        func loadKeyData(service: String, account: String) throws -> Data?
        func deleteKeyData(service: String, account: String) throws
    }

    final class KeychainKeyStorage: KeyStorage {
        func saveKeyData(_ data: Data, service: String, account: String, accessibility: CFString) throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessible as String: accessibility,
                kSecValueData as String: data
            ]
            SecItemDelete(query as CFDictionary)
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw SecurityError.keyStoreFailed(status)
            }
            AppLogger.security.notice("Encryption key stored in Keychain.")
        }

        func loadKeyData(service: String, account: String) throws -> Data? {
            let authenticationContext = LAContext()
            authenticationContext.interactionNotAllowed = true
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: authenticationContext
            ]
            var dataTypeRef: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
            if status == errSecSuccess {
                return dataTypeRef as? Data
            }
            if status == errSecItemNotFound {
                return nil
            }
            throw SecurityError.keyLoadFailed(status)
        }

        func deleteKeyData(service: String, account: String) throws {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecurityError.keyStoreFailed(status)
            }
        }
    }

    final class InMemoryKeyStorage: KeyStorage, @unchecked Sendable {
        private var keys: [String: Data] = [:]
        private let lock = NSLock()

        init(initialKeys: [String: Data] = [:]) {
            self.keys = initialKeys
        }

        func saveKeyData(_ data: Data, service: String, account: String, accessibility: CFString) throws {
            lock.lock()
            defer { lock.unlock() }
            keys[Self.key(service: service, account: account)] = data
        }

        func loadKeyData(service: String, account: String) throws -> Data? {
            lock.lock()
            defer { lock.unlock() }
            return keys[Self.key(service: service, account: account)]
        }

        func deleteKeyData(service: String, account: String) throws {
            lock.lock()
            defer { lock.unlock() }
            keys.removeValue(forKey: Self.key(service: service, account: account))
        }

        private static func key(service: String, account: String) -> String {
            "\(service)\u{1f}\(account)"
        }
    }

    static let shared = SecurityManager()
    private static let authenticatedCiphertextPrefix = "forkclip-aad-v1:"
    private static let defaultBlacklistBundleIDs = [
        "com.1password.1password",
        "com.1password.1password.helper",
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.apple.keychainaccess",
        "com.apple.passwords",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.dashlane.dashlane",
        "org.keepassxc.keepassxc"
    ]
    private let keyService = "com.user.forkclip.encryption"
    private let keyAccount = "symmetricKey"
    private let keyAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    private let keyStorage: KeyStorage
    private let defaultBlacklistBundleIDs: [String]
    private let blacklistConfigURL: URL?
    private let customSecretPatternsURL: URL?
    private let stateLock = NSLock()
    private var configuredBlacklistBundleIDs: [String] = []
    private var configuredSecretPatterns: [CustomSecretPattern] = []
    private var configuredSecretRegexes: [NSRegularExpression] = []
    private var storedLastError: SecurityError?
    private var storedKeyState: SecurityKeyState = .unchecked

    enum SecurityError: LocalizedError, Equatable, Sendable {
        case keyGenerationFailed
        case keyStoreFailed(OSStatus)
        case keyLoadFailed(OSStatus)
        case keyMissing
        case invalidCiphertext
        case decryptFailed

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                return "暗号鍵の生成に失敗しました。"
            case .keyStoreFailed(let status):
                return "暗号鍵の保存に失敗しました。(status: \(status))"
            case .keyLoadFailed(let status):
                return "暗号鍵の読込に失敗しました。(status: \(status))"
            case .keyMissing:
                return "暗号鍵が見つかりません。既存データを復号できない可能性があります。"
            case .invalidCiphertext:
                return "保存データの形式が不正です。"
            case .decryptFailed:
                return "保存データの復号に失敗しました。"
            }
        }
    }

    private(set) var lastError: SecurityError? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return storedLastError
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            storedLastError = newValue
        }
    }

    private(set) var keyState: SecurityKeyState {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return storedKeyState
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            storedKeyState = newValue
        }
    }

    init(
        blacklistBundleIDs: [String] = SecurityManager.defaultBlacklistBundleIDs,
        blacklistConfigURL: URL? = nil,
        customSecretPatternsURL: URL? = nil,
        keyStorage: KeyStorage = KeychainKeyStorage()
    ) {
        self.defaultBlacklistBundleIDs = blacklistBundleIDs
        self.blacklistConfigURL = blacklistConfigURL
        self.customSecretPatternsURL = customSecretPatternsURL
        self.keyStorage = keyStorage
        reloadApplicationBlacklist()
        reloadCustomSecretPatterns()
    }

    // --- Encryption ---
    func encrypt(_ text: String, context: EncryptionContext? = nil) -> String? {
        do {
            let key = try getEncryptionKey()
            guard let data = text.data(using: .utf8) else { return nil }

            let sealedBox: AES.GCM.SealedBox
            if let context {
                sealedBox = try AES.GCM.seal(data, using: key, authenticating: context.authenticatedData)
            } else {
                sealedBox = try AES.GCM.seal(data, using: key)
            }
            lastError = nil
            keyState = .available
            guard let encodedCiphertext = sealedBox.combined?.base64EncodedString() else {
                return nil
            }
            return context == nil
                ? encodedCiphertext
                : Self.authenticatedCiphertextPrefix + encodedCiphertext
        } catch let error as SecurityError {
            lastError = error
            keyState = .failed
            AppLogger.security.error("Encryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        } catch {
            lastError = .keyGenerationFailed
            keyState = .failed
            AppLogger.security.error("Encryption failed with unknown error.")
            return nil
        }
    }

    func decrypt(_ base64Encoded: String, context: EncryptionContext? = nil) -> String? {
        do {
            let key = try getExistingEncryptionKey()
            let isAuthenticatedCiphertext = base64Encoded.hasPrefix(Self.authenticatedCiphertextPrefix)
            let encodedCiphertext = isAuthenticatedCiphertext
                ? String(base64Encoded.dropFirst(Self.authenticatedCiphertextPrefix.count))
                : base64Encoded
            guard let combinedData = Data(base64Encoded: encodedCiphertext) else {
                throw SecurityError.invalidCiphertext
            }
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            let decryptedData: Data
            if isAuthenticatedCiphertext {
                guard let context else {
                    throw SecurityError.decryptFailed
                }
                decryptedData = try AES.GCM.open(sealedBox, using: key, authenticating: context.authenticatedData)
            } else {
                decryptedData = try AES.GCM.open(sealedBox, using: key)
            }
            lastError = nil
            keyState = .available
            return String(data: decryptedData, encoding: .utf8)
        } catch let error as SecurityError {
            lastError = error
            keyState = error == .keyMissing ? .missing : .failed
            AppLogger.security.error("Decryption failed: \(error.localizedDescription, privacy: .public)")
            return nil
        } catch {
            lastError = .decryptFailed
            keyState = .failed
            AppLogger.security.error("Decryption failed with unknown error.")
            return nil
        }
    }

    func resetLastError() {
        lastError = nil
    }

    func currentKeyState() -> SecurityKeyState {
        do {
            let keyData = try loadPreferredKeyData()
            keyState = keyData == nil ? .missing : .available
        } catch let error as SecurityError {
            lastError = error
            keyState = .failed
            AppLogger.security.error("Key state inspection failed: \(error.localizedDescription, privacy: .public)")
        } catch {
            keyState = .failed
            AppLogger.security.error("Key state inspection failed with unknown error.")
        }
        return keyState
    }

    @discardableResult
    func ensureEncryptionKeyExists() -> Bool {
        do {
            _ = try getEncryptionKey()
            keyState = .available
            return true
        } catch let error as SecurityError {
            lastError = error
            keyState = .failed
            AppLogger.security.error("Ensuring encryption key failed: \(error.localizedDescription, privacy: .public)")
            return false
        } catch {
            lastError = .keyGenerationFailed
            keyState = .failed
            AppLogger.security.error("Ensuring encryption key failed with unknown error.")
            return false
        }
    }

    @discardableResult
    func replaceMissingKey() -> Bool {
        do {
            try keyStorage.deleteKeyData(service: keyService, account: keyAccount)
            _ = try getEncryptionKey()
            lastError = nil
            keyState = .available
            AppLogger.security.notice("Encryption key was recreated after recovery flow.")
            return true
        } catch let error as SecurityError {
            lastError = error
            keyState = .failed
            AppLogger.security.error("Replacing encryption key failed: \(error.localizedDescription, privacy: .public)")
            return false
        } catch {
            lastError = .keyGenerationFailed
            keyState = .failed
            AppLogger.security.error("Replacing encryption key failed with unknown error.")
            return false
        }
    }

    private func getEncryptionKey() throws -> SymmetricKey {
        if let keyData = try loadPreferredKeyData() {
            return SymmetricKey(data: keyData)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try keyStorage.saveKeyData(
            keyData,
            service: keyService,
            account: keyAccount,
            accessibility: keyAccessibility
        )
        return newKey
    }

    private func getExistingEncryptionKey() throws -> SymmetricKey {
        guard let keyData = try loadPreferredKeyData() else {
            throw SecurityError.keyMissing
        }
        return SymmetricKey(data: keyData)
    }

    private func loadPreferredKeyData() throws -> Data? {
        try keyStorage.loadKeyData(service: keyService, account: keyAccount)
    }

    // --- Custom Secret Patterns ---
    var customSecretPatterns: [CustomSecretPattern] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return configuredSecretPatterns
    }

    func saveCustomSecretPatterns(_ patterns: [CustomSecretPattern]) throws {
        let configURL: URL
        if let customSecretPatternsURL {
            configURL = customSecretPatternsURL
        } else {
            configURL = try AppPaths.customSecretPatternsURL()
        }
        try CustomSecretPatternStore.save(patterns, to: configURL)
        try loadCustomSecretPatterns(from: configURL)
    }

    func reloadCustomSecretPatterns() {
        let configURL = customSecretPatternsURL ?? (try? AppPaths.customSecretPatternsURL())
        guard let configURL else {
            replaceCustomSecretPatterns([])
            return
        }

        do {
            try loadCustomSecretPatterns(from: configURL)
        } catch {
            replaceCustomSecretPatterns([])
            AppLogger.security.error("Failed to load custom secret patterns: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadCustomSecretPatterns(from configURL: URL) throws {
        let patterns = try CustomSecretPatternStore.load(from: configURL)
        replaceCustomSecretPatterns(patterns)
    }

    private func replaceCustomSecretPatterns(_ patterns: [CustomSecretPattern]) {
        let regexes = CustomSecretPatternValidator.compiledRegexes(for: patterns)
        stateLock.lock()
        configuredSecretPatterns = patterns
        configuredSecretRegexes = regexes
        stateLock.unlock()
    }

    private func matchesCustomSecretPattern(_ text: String) -> Bool {
        stateLock.lock()
        let regexes = configuredSecretRegexes
        stateLock.unlock()

        return regexes.contains { regex in
            CustomSecretPatternValidator.firstMatch(in: text, regex: regex) != nil
        }
    }

    // --- Entropy Analysis ---
    func isLikelySecret(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if matchesCustomSecretPattern(trimmed) { return true }
        if containsPrivateKeyBlock(trimmed) { return true }
        if containsExplicitCredential(trimmed) { return true }
        if trimmed.count < 8 { return false }
        if looksLikeURL(trimmed) { return false }

        if hasKnownSecretPrefix(trimmed) { return true }
        if isKnownStructuredSecret(trimmed) { return true }
        if isLikelyJWT(trimmed) { return true }
        if containsCJKCharacters(trimmed) { return false }
        if looksLikeNaturalLanguage(trimmed) { return false }

        let entropy = shannonEntropy(of: trimmed)
        let longStructuredToken = trimmed.count >= 32
            && containsMixedCharacterClasses(trimmed)
            && containsNoWhitespace(trimmed)

        return entropy > 4.0 && longStructuredToken
    }

    private func shannonEntropy(of text: String) -> Double {
        let frequencies = text.reduce(into: [Character: Int]()) { $0[$1, default: 0] += 1 }
        return frequencies.values.reduce(0.0) { (acc, count) -> Double in
            let p = Double(count) / Double(text.count)
            return acc - (p * log2(p))
        }
    }

    private func containsMixedCharacterClasses(_ text: String) -> Bool {
        let hasLowercase = text.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasUppercase = text.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasDigits = text.rangeOfCharacter(from: .decimalDigits) != nil
        let symbols = CharacterSet.alphanumerics.inverted
        let hasSymbols = text.rangeOfCharacter(from: symbols) != nil
        return [hasLowercase, hasUppercase, hasDigits, hasSymbols].filter { $0 }.count >= 3
    }

    private func looksLikeURL(_ text: String) -> Bool {
        text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    private func looksLikeNaturalLanguage(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return words.count >= 4 && text.rangeOfCharacter(from: .punctuationCharacters) == nil
    }

    private func containsNoWhitespace(_ text: String) -> Bool {
        text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    private func containsCJKCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }

    private func containsPrivateKeyBlock(_ text: String) -> Bool {
        text.range(of: #"-----BEGIN\s+[A-Z ]*PRIVATE KEY-----"#, options: .regularExpression) != nil
    }

    private func hasKnownSecretPrefix(_ text: String) -> Bool {
        let knownPrefixes = [
            "sk-ant-",
            "sk_live_",
            "sk_test_",
            "rk_live_",
            "rk_test_",
            "sk_org_",
            "sk-",
            "ghp_",
            "github_pat_",
            "xoxb-",
            "xoxp-",
            "AIza",
            "AKIA",
            "ASIA",
            "eyJ",
            "glpat-",
            "gloas-",
            "gldt-",
            "glrt-",
            "glrtr-",
            "glcbt-",
            "glptt-",
            "glft-",
            "glimt-",
            "glagent-",
            "glwt-",
            "glsoat-"
        ]

        return containsNoWhitespace(text) && knownPrefixes.contains { text.hasPrefix($0) }
    }

    private func isKnownStructuredSecret(_ text: String) -> Bool {
        text.range(of: #"^SK[0-9a-fA-F]{32}$"#, options: .regularExpression) != nil
    }

    private func containsExplicitCredential(_ text: String) -> Bool {
        let meaningfulLines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }

        let linesToCheck = meaningfulLines.isEmpty
            ? [text.trimmingCharacters(in: .whitespacesAndNewlines)]
            : meaningfulLines

        guard !linesToCheck.isEmpty,
              linesToCheck.allSatisfy(isConfigurationLine) else {
            return false
        }
        return linesToCheck.contains(where: isCredentialLine)
    }

    private func isCredentialLine(_ line: String) -> Bool {
        if isAuthorizationCredentialLine(line) || isBearerCredentialLine(line) {
            return true
        }

        guard let assignment = parsedCredentialAssignment(from: line) else {
            return false
        }

        let normalizedKey = normalizedCredentialKey(assignment.key)
        let longSecretKeys: Set<String> = [
            "api_key",
            "auth_token",
            "client_secret",
            "password",
            "passwd",
            "private_key",
            "refresh_token",
            "secret",
            "secret_key",
            "token"
        ]
        let shortSecretKeys: Set<String> = [
            "2fa_code",
            "mfa_code",
            "one_time_password",
            "otp",
            "passcode",
            "pin",
            "verification_code"
        ]
        let cjkLongSecretKeys: Set<String> = ["トークン", "パスワード", "秘密"]
        let cjkShortSecretKeys: Set<String> = ["ワンタイムパスワード", "暗証番号", "確認コード", "認証コード"]

        if longSecretKeys.contains(normalizedKey) || cjkLongSecretKeys.contains(assignment.key) {
            return isCredentialValue(assignment.value, minimumLength: 8)
        }

        if shortSecretKeys.contains(normalizedKey) || cjkShortSecretKeys.contains(assignment.key) {
            return isCredentialValue(assignment.value, minimumLength: 4, maximumLength: 12, requiresDigit: true)
        }

        return false
    }

    private func isConfigurationLine(_ line: String) -> Bool {
        if isAuthorizationCredentialLine(line) || isBearerCredentialLine(line) {
            return true
        }
        guard let assignment = parsedCredentialAssignment(from: line) else {
            return false
        }
        return isCompactConfigurationKey(assignment.key)
    }

    private func isAuthorizationCredentialLine(_ line: String) -> Bool {
        let authorizationPattern = #"(?i)^authorization\b\s*[:=]\s*(bearer\s+)?["']?[^"'\s]{8,}["']?\s*$"#
        return line.range(of: authorizationPattern, options: .regularExpression) != nil
    }

    private func isBearerCredentialLine(_ line: String) -> Bool {
        let bearerPattern = #"(?i)^bearer\s+[^"'\s]{8,}\s*$"#
        return line.range(of: bearerPattern, options: .regularExpression) != nil
    }

    private func parsedCredentialAssignment(from line: String) -> (key: String, value: String)? {
        var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.lowercased().hasPrefix("export ") {
            candidate = String(candidate.dropFirst("export ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let separatorIndex = candidate.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return nil
        }

        let key = String(candidate[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(candidate[candidate.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if let commentRange = value.range(of: #"\s+#.*$"#, options: .regularExpression) {
            value.removeSubrange(commentRange)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !key.isEmpty && !value.isEmpty else {
            return nil
        }

        return (key, strippedWrappingQuotes(from: value))
    }

    private func isCompactConfigurationKey(_ key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedKey.count <= 40 else { return false }
        if containsCJKCharacters(trimmedKey) {
            return trimmedKey.split(separator: " ").count <= 2
        }
        guard trimmedKey.range(of: #"^[A-Za-z][A-Za-z0-9_ -]*$"#, options: .regularExpression) != nil else {
            return false
        }
        return trimmedKey.split(separator: " ").count <= 3
    }

    private func normalizedCredentialKey(_ key: String) -> String {
        key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func strippedWrappingQuotes(from value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private func isCredentialValue(
        _ value: String,
        minimumLength: Int,
        maximumLength: Int? = nil,
        requiresDigit: Bool = false
    ) -> Bool {
        guard value.count >= minimumLength else { return false }
        if let maximumLength, value.count > maximumLength { return false }
        guard containsNoWhitespace(value) else { return false }
        if requiresDigit && value.rangeOfCharacter(from: .decimalDigits) == nil {
            return false
        }
        return true
    }

    private func isLikelyJWT(_ text: String) -> Bool {
        let segments = text.split(separator: ".")
        guard segments.count == 3 else { return false }
        return segments.allSatisfy { segment in
            segment.range(of: #"^[A-Za-z0-9\-_]+$"#, options: .regularExpression) != nil
        }
    }

    // --- App Blacklist ---
    func reloadApplicationBlacklist() {
        let configURL = blacklistConfigURL ?? (try? AppPaths.blacklistURL())
        guard let configURL, FileManager.default.fileExists(atPath: configURL.path) else {
            stateLock.lock()
            configuredBlacklistBundleIDs = []
            stateLock.unlock()
            return
        }

        do {
            let rawText = try String(contentsOf: configURL, encoding: .utf8)
            let configuredBundleIDs = rawText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .map { $0.lowercased() }
            stateLock.lock()
            configuredBlacklistBundleIDs = configuredBundleIDs
            stateLock.unlock()
        } catch {
            stateLock.lock()
            configuredBlacklistBundleIDs = []
            stateLock.unlock()
            AppLogger.security.error("Failed to load application blacklist config: \(String(describing: error), privacy: .public)")
        }
    }

    func isApplicationBlacklisted(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        let lowerID = bundleID.lowercased()
        stateLock.lock()
        let configuredBundleIDs = configuredBlacklistBundleIDs
        stateLock.unlock()
        let blacklistBundleIDs = defaultBlacklistBundleIDs.map { $0.lowercased() } + configuredBundleIDs
        return blacklistBundleIDs.contains { blacklistRuleMatches(bundleID: lowerID, rule: $0) }
    }

    private func blacklistRuleMatches(bundleID: String, rule: String) -> Bool {
        let normalizedRule = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedRule.isEmpty else { return false }

        if normalizedRule.hasSuffix(".*") {
            let prefix = String(normalizedRule.dropLast(2))
            return bundleID == prefix || bundleID.hasPrefix(prefix + ".")
        }

        if normalizedRule.hasSuffix("*") {
            let prefix = String(normalizedRule.dropLast())
            return !prefix.isEmpty && bundleID.hasPrefix(prefix)
        }

        return bundleID == normalizedRule || bundleID.hasPrefix(normalizedRule + ".")
    }
}
