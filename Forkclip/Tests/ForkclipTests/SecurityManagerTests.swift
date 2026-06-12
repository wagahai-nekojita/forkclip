#if canImport(XCTest)
import XCTest
@testable import Forkclip

@MainActor
final class SecurityManagerTests: XCTestCase {
    private let security = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())

    func testDefaultBlacklistedApplicationsAreDetected() {
        let manager = SecurityManager()

        XCTAssertTrue(manager.isApplicationBlacklisted("com.1password.1password"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.1password.1password.helper"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.agilebits.onepassword"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.agilebits.onepassword7"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.apple.keychainaccess"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.apple.Passwords"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.bitwarden.desktop"))
        XCTAssertTrue(manager.isApplicationBlacklisted("org.keepassxc.KeePassXC"))
        XCTAssertFalse(manager.isApplicationBlacklisted("com.example.editor"))
        XCTAssertFalse(manager.isApplicationBlacklisted("com.example.onepasswordnotes"))
    }

    func testConfiguredBlacklistFileIsLoaded() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("blacklist_bundle_ids.txt")
        try """
        # custom blacklist
        com.example.SecretApp

        com.example.PasswordManager
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = SecurityManager(blacklistBundleIDs: [], blacklistConfigURL: configURL)

        XCTAssertTrue(manager.isApplicationBlacklisted("com.example.secretapp.helper"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.example.passwordmanager"))
        XCTAssertFalse(manager.isApplicationBlacklisted("com.example.notsecretapp"))
        XCTAssertFalse(manager.isApplicationBlacklisted("com.example.secretapplication"))
        XCTAssertFalse(manager.isApplicationBlacklisted("com.example.editor"))
    }

    func testReloadApplicationBlacklistRefreshesConfigFile() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("blacklist_bundle_ids.txt")
        try "com.example.first".write(to: configURL, atomically: true, encoding: .utf8)
        let manager = SecurityManager(blacklistBundleIDs: [], blacklistConfigURL: configURL)

        XCTAssertTrue(manager.isApplicationBlacklisted("com.example.first"))

        try "com.example.second".write(to: configURL, atomically: true, encoding: .utf8)
        manager.reloadApplicationBlacklist()

        XCTAssertFalse(manager.isApplicationBlacklisted("com.example.first"))
        XCTAssertTrue(manager.isApplicationBlacklisted("com.example.second"))
    }

    func testKnownPrefixIsDetectedAsSecret() {
        XCTAssertTrue(security.isLikelySecret("sk-test-1234567890ABCDEFG"))
        XCTAssertTrue(security.isLikelySecret("ghp_1234567890abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(security.isLikelySecret("sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890"))
        XCTAssertTrue(security.isLikelySecret("rk_live_1234567890abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(security.isLikelySecret("glpat-1234567890abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(security.isLikelySecret("SK0123456789abcdef0123456789abcdef"))
    }

    func testNaturalLanguageIsNotDetectedAsSecret() {
        XCTAssertFalse(security.isLikelySecret("this is a regular sentence for clipboard history"))
        XCTAssertFalse(security.isLikelySecret("https://example.com/docs/reference"))
    }

    func testFormattedNormalTextIsNotDetectedAsSecret() {
        let examples = [
            """
            ほとんどが非公開になってしまっている。原因を調査して Issue を立てる。
            Atlas / Codex / Claude 由来の履歴がマスク表示になっている。
            """,
            "ほとんどが非公開になってしまっている。Atlas/Codex/Claude由来の履歴がマスク表示になっている。",
            """
            # Dashboard status
            - Private: OFF
            - Queue: 0
            - Validation: swift test --scratch-path /tmp/forkclip-validation-test-build
            """,
            """
            func renderPreview(itemCount: Int) -> String {
                return "Private OFF / Queue 0 / Status OK"
            }
            """
        ]

        for example in examples {
            XCTAssertFalse(security.isLikelySecret(example), example)
        }
    }

    func testCredentialWordsInNormalProseAreNotDetectedAsSecret() {
        XCTAssertFalse(security.isLikelySecret("The token budget and password field labels are part of documentation, not credentials."))
        XCTAssertFalse(security.isLikelySecret("今日の認証コードについてのドキュメントを更新する"))
        XCTAssertFalse(security.isLikelySecret("SKThisIsNotATwilioSID"))
    }

    func testLongNormalTextWithCredentialExampleIsNotDetectedAsSecret() {
        let example = """
        This review explains why examples such as token=abc123DEF456!@#7890 should not make an entire long response private.
        The copied text is documentation mixed with prose, issue notes, and validation commands.
        It should remain visible unless the clipboard content itself is a compact credential.
        """

        XCTAssertFalse(security.isLikelySecret(example))
    }

    func testJWTIsDetectedAsSecret() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTYifQ.signatureValue123"
        XCTAssertTrue(security.isLikelySecret(jwt))
    }

    func testSecretAssignmentsAreDetectedAsSecret() {
        XCTAssertTrue(security.isLikelySecret("token=abc123DEF456!@#7890"))
        XCTAssertTrue(security.isLikelySecret("password=abc123DEF456!@#7890"))
        XCTAssertTrue(security.isLikelySecret("API_KEY=abc123DEF4567890\nTOKEN=def456ABC7890123"))
        XCTAssertTrue(security.isLikelySecret("API_KEY=abc123DEF4567890\nREGION=us-east-1\nDEBUG=false"))
        XCTAssertTrue(security.isLikelySecret("Authorization: Bearer abc123DEF4567890"))
        XCTAssertTrue(security.isLikelySecret("pin=123456"))
        XCTAssertTrue(security.isLikelySecret("otp: 654321"))
        XCTAssertTrue(security.isLikelySecret("verification_code=123456"))
        XCTAssertTrue(security.isLikelySecret("認証コード=123456"))
        XCTAssertTrue(security.isLikelySecret("パスワード=abc123DEF456"))
    }

    func testPrivateKeyBlockIsDetectedAsSecret() {
        XCTAssertTrue(security.isLikelySecret("-----BEGIN PRIVATE KEY-----\nabc123DEF456\n-----END PRIVATE KEY-----"))
    }

    func testCustomSecretPatternsCanBeSavedLoadedAndApplied() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("custom_secret_patterns.json")
        let manager = SecurityManager(
            customSecretPatternsURL: configURL,
            keyStorage: SecurityManager.InMemoryKeyStorage()
        )

        try manager.saveCustomSecretPatterns([
            CustomSecretPattern(name: "Internal deploy token", pattern: #"DEPLOY-[A-Z0-9]{16}"#)
        ])

        XCTAssertEqual(manager.customSecretPatterns, [
            CustomSecretPattern(name: "Internal deploy token", pattern: #"DEPLOY-[A-Z0-9]{16}"#)
        ])
        XCTAssertTrue(manager.isLikelySecret("DEPLOY-ABCDEF1234567890"))
        XCTAssertFalse(manager.isLikelySecret("DEPLOY-token-for-documentation"))
        XCTAssertFalse(manager.isLikelySecret("this is a regular sentence for clipboard history"))

        let reopenedManager = SecurityManager(
            customSecretPatternsURL: configURL,
            keyStorage: SecurityManager.InMemoryKeyStorage()
        )
        XCTAssertTrue(reopenedManager.isLikelySecret("DEPLOY-ZYXWVU9876543210"))
    }

    func testInvalidCustomSecretPatternsAreRejectedAndNotApplied() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("custom_secret_patterns.json")
        let manager = SecurityManager(
            customSecretPatternsURL: configURL,
            keyStorage: SecurityManager.InMemoryKeyStorage()
        )

        XCTAssertThrowsError(try manager.saveCustomSecretPatterns([
            CustomSecretPattern(name: "Broken", pattern: #"[abc"#)
        ])) { error in
            XCTAssertEqual(error as? CustomSecretPatternValidationError, .invalidRegex)
        }

        XCTAssertThrowsError(try manager.saveCustomSecretPatterns([
            CustomSecretPattern(name: "Empty", pattern: #".*"#)
        ])) { error in
            XCTAssertEqual(error as? CustomSecretPatternValidationError, .matchesEmptyString)
        }

        XCTAssertThrowsError(try manager.saveCustomSecretPatterns([
            CustomSecretPattern(name: "Broad", pattern: #"hello"#)
        ])) { error in
            XCTAssertEqual(error as? CustomSecretPatternValidationError, .tooBroad("hello"))
        }

        XCTAssertTrue(manager.customSecretPatterns.isEmpty)
        XCTAssertFalse(manager.isLikelySecret("hello"))
    }

    func testReloadCustomSecretPatternsDropsInvalidConfigurationSafely() throws {
        let tempDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let configURL = tempDirectory.appendingPathComponent("custom_secret_patterns.json")
        try """
        [
          {
            "name": "Broad prose matcher",
            "pattern": "regular sentence"
          }
        ]
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = SecurityManager(
            customSecretPatternsURL: configURL,
            keyStorage: SecurityManager.InMemoryKeyStorage()
        )

        XCTAssertTrue(manager.customSecretPatterns.isEmpty)
        XCTAssertFalse(manager.isLikelySecret("this is a regular sentence for clipboard history"))
    }

    func testEncryptionContextRejectsMismatchAndReadsLegacyCiphertext() throws {
        let itemID = UUID()
        let otherItemID = UUID()
        let legacyCiphertext = try XCTUnwrap(security.encrypt("legacy value"))

        XCTAssertEqual(
            security.decrypt(legacyCiphertext, context: .itemContent(itemID: itemID)),
            "legacy value"
        )

        let boundCiphertext = try XCTUnwrap(security.encrypt(
            "bound value",
            context: .itemContent(itemID: itemID)
        ))

        XCTAssertEqual(
            security.decrypt(boundCiphertext, context: .itemContent(itemID: itemID)),
            "bound value"
        )
        XCTAssertNil(Data(base64Encoded: boundCiphertext))
        XCTAssertNil(security.decrypt(boundCiphertext))
        XCTAssertNil(security.decrypt(boundCiphertext, context: .itemContent(itemID: otherItemID)))
    }

    func testEncryptionKeyCanBePreparedDuringStartupCheck() {
        XCTAssertTrue(security.ensureEncryptionKeyExists())
        XCTAssertEqual(security.currentKeyState(), .available)
    }

    func testEncryptionUsesInjectedKeyStorage() throws {
        let storage = SecurityManager.InMemoryKeyStorage()
        let firstManager = SecurityManager(keyStorage: storage)
        let ciphertext = try XCTUnwrap(firstManager.encrypt("isolated value"))

        let reopenedManager = SecurityManager(keyStorage: storage)
        XCTAssertEqual(reopenedManager.decrypt(ciphertext), "isolated value")

        let unrelatedManager = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
        XCTAssertNil(unrelatedManager.decrypt(ciphertext))
    }

    func testDuplicateContentDigestUsesInjectedKeyMaterial() throws {
        let storage = SecurityManager.InMemoryKeyStorage()
        let firstManager = SecurityManager(keyStorage: storage)
        XCTAssertTrue(firstManager.ensureEncryptionKeyExists())
        let digest = try XCTUnwrap(firstManager.duplicateContentDigest(for: "repeat value"))

        let reopenedManager = SecurityManager(keyStorage: storage)
        XCTAssertEqual(reopenedManager.duplicateContentDigest(for: "repeat value"), digest)

        let unrelatedManager = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
        XCTAssertTrue(unrelatedManager.ensureEncryptionKeyExists())
        XCTAssertNotEqual(unrelatedManager.duplicateContentDigest(for: "repeat value"), digest)
        XCTAssertFalse(digest.contains("repeat value"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory
    }
}
#elseif canImport(Testing)
import Testing
@testable import Forkclip

@MainActor
struct SecurityManagerTests {
    private let security = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())

    @Test
    func defaultBlacklistedApplicationsAreDetected() {
        let manager = SecurityManager()

        #expect(manager.isApplicationBlacklisted("com.1password.1password"))
        #expect(manager.isApplicationBlacklisted("com.1password.1password.helper"))
        #expect(manager.isApplicationBlacklisted("com.agilebits.onepassword"))
        #expect(manager.isApplicationBlacklisted("com.agilebits.onepassword7"))
        #expect(manager.isApplicationBlacklisted("com.apple.keychainaccess"))
        #expect(manager.isApplicationBlacklisted("com.apple.Passwords"))
        #expect(manager.isApplicationBlacklisted("com.bitwarden.desktop"))
        #expect(manager.isApplicationBlacklisted("org.keepassxc.KeePassXC"))
        #expect(manager.isApplicationBlacklisted("com.example.editor") == false)
        #expect(manager.isApplicationBlacklisted("com.example.onepasswordnotes") == false)
    }

    @Test
    func knownPrefixIsDetectedAsSecret() {
        #expect(security.isLikelySecret("sk-test-1234567890ABCDEFG"))
        #expect(security.isLikelySecret("ghp_1234567890abcdefghijklmnopqrstuvwxyz"))
        #expect(security.isLikelySecret("sk-ant-api03-abcdefghijklmnopqrstuvwxyz1234567890"))
        #expect(security.isLikelySecret("rk_live_1234567890abcdefghijklmnopqrstuvwxyz"))
        #expect(security.isLikelySecret("glpat-1234567890abcdefghijklmnopqrstuvwxyz"))
        #expect(security.isLikelySecret("SK0123456789abcdef0123456789abcdef"))
    }

    @Test
    func naturalLanguageIsNotDetectedAsSecret() {
        #expect(security.isLikelySecret("this is a regular sentence for clipboard history") == false)
        #expect(security.isLikelySecret("https://example.com/docs/reference") == false)
    }

    @Test
    func formattedNormalTextIsNotDetectedAsSecret() {
        let examples = [
            """
            ほとんどが非公開になってしまっている。原因を調査して Issue を立てる。
            Atlas / Codex / Claude 由来の履歴がマスク表示になっている。
            """,
            "ほとんどが非公開になってしまっている。Atlas/Codex/Claude由来の履歴がマスク表示になっている。",
            """
            # Dashboard status
            - Private: OFF
            - Queue: 0
            - Validation: swift test --scratch-path /tmp/forkclip-validation-test-build
            """,
            """
            func renderPreview(itemCount: Int) -> String {
                return "Private OFF / Queue 0 / Status OK"
            }
            """
        ]

        for example in examples {
            #expect(security.isLikelySecret(example) == false)
        }
    }

    @Test
    func credentialWordsInNormalProseAreNotDetectedAsSecret() {
        #expect(security.isLikelySecret("The token budget and password field labels are part of documentation, not credentials.") == false)
        #expect(security.isLikelySecret("今日の認証コードについてのドキュメントを更新する") == false)
        #expect(security.isLikelySecret("SKThisIsNotATwilioSID") == false)
    }

    @Test
    func longNormalTextWithCredentialExampleIsNotDetectedAsSecret() {
        let example = """
        This review explains why examples such as token=abc123DEF456!@#7890 should not make an entire long response private.
        The copied text is documentation mixed with prose, issue notes, and validation commands.
        It should remain visible unless the clipboard content itself is a compact credential.
        """

        #expect(security.isLikelySecret(example) == false)
    }

    @Test
    func jwtIsDetectedAsSecret() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTYifQ.signatureValue123"
        #expect(security.isLikelySecret(jwt))
    }

    @Test
    func secretAssignmentsAreDetectedAsSecret() {
        #expect(security.isLikelySecret("token=abc123DEF456!@#7890"))
        #expect(security.isLikelySecret("password=abc123DEF456!@#7890"))
        #expect(security.isLikelySecret("API_KEY=abc123DEF4567890\nTOKEN=def456ABC7890123"))
        #expect(security.isLikelySecret("API_KEY=abc123DEF4567890\nREGION=us-east-1\nDEBUG=false"))
        #expect(security.isLikelySecret("Authorization: Bearer abc123DEF4567890"))
        #expect(security.isLikelySecret("pin=123456"))
        #expect(security.isLikelySecret("otp: 654321"))
        #expect(security.isLikelySecret("verification_code=123456"))
        #expect(security.isLikelySecret("認証コード=123456"))
        #expect(security.isLikelySecret("パスワード=abc123DEF456"))
    }

    @Test
    func privateKeyBlockIsDetectedAsSecret() {
        #expect(security.isLikelySecret("-----BEGIN PRIVATE KEY-----\nabc123DEF456\n-----END PRIVATE KEY-----"))
    }

    @Test
    func encryptionContextRejectsMismatchAndReadsLegacyCiphertext() throws {
        let itemID = UUID()
        let otherItemID = UUID()
        let legacyCiphertext = try #require(security.encrypt("legacy value"))

        #expect(security.decrypt(legacyCiphertext, context: .itemContent(itemID: itemID)) == "legacy value")

        let boundCiphertext = try #require(security.encrypt(
            "bound value",
            context: .itemContent(itemID: itemID)
        ))

        #expect(security.decrypt(boundCiphertext, context: .itemContent(itemID: itemID)) == "bound value")
        #expect(Data(base64Encoded: boundCiphertext) == nil)
        #expect(security.decrypt(boundCiphertext) == nil)
        #expect(security.decrypt(boundCiphertext, context: .itemContent(itemID: otherItemID)) == nil)
    }

    @Test
    func encryptionKeyCanBePreparedDuringStartupCheck() {
        #expect(security.ensureEncryptionKeyExists())
        #expect(security.currentKeyState() == .available)
    }

    @Test
    func encryptionUsesInjectedKeyStorage() throws {
        let storage = SecurityManager.InMemoryKeyStorage()
        let firstManager = SecurityManager(keyStorage: storage)
        let ciphertext = try #require(firstManager.encrypt("isolated value"))

        let reopenedManager = SecurityManager(keyStorage: storage)
        #expect(reopenedManager.decrypt(ciphertext) == "isolated value")

        let unrelatedManager = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
        #expect(unrelatedManager.decrypt(ciphertext) == nil)
    }

    @Test
    func duplicateContentDigestUsesInjectedKeyMaterial() throws {
        let storage = SecurityManager.InMemoryKeyStorage()
        let firstManager = SecurityManager(keyStorage: storage)
        #expect(firstManager.ensureEncryptionKeyExists())
        let digest = try #require(firstManager.duplicateContentDigest(for: "repeat value"))

        let reopenedManager = SecurityManager(keyStorage: storage)
        #expect(reopenedManager.duplicateContentDigest(for: "repeat value") == digest)

        let unrelatedManager = SecurityManager(keyStorage: SecurityManager.InMemoryKeyStorage())
        #expect(unrelatedManager.ensureEncryptionKeyExists())
        #expect(unrelatedManager.duplicateContentDigest(for: "repeat value") != digest)
        #expect(digest.contains("repeat value") == false)
    }
}
#endif
