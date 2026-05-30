#if canImport(XCTest)
import XCTest
@testable import Forkclip

@MainActor
final class AppSettingsTests: XCTestCase {
    func testSettingsSaveAndLoadRoundTrip() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("app_settings.json")
        let retentionURL = tempDirectory.appendingPathComponent("retention_policy.json")
        let store = AppSettingsStore(
            settingsURL: settingsURL,
            retentionPolicyURL: retentionURL,
            appliesRetentionToSharedDatabase: false
        )

        store.settings = AppSettings(
            historyLayout: .list,
            panelPlacement: .top,
            panelSizePreset: .custom,
            customPanelWidth: 1_180,
            customPanelHeight: 520,
            folderSidebarVisibility: .always,
            appearanceMode: .dark,
            copyFeedbackSoundEnabled: false,
            copyFeedbackAnimationEnabled: false,
            autoPasteOnCardSelection: true,
            launchAtLogin: true,
            fetchLimit: 240,
            maxStoredItems: 600,
            maxAgeDays: 45,
            privateModeOnLaunch: true
        )

        XCTAssertTrue(store.save())
        XCTAssertEqual(AppSettings.load(from: settingsURL), store.settings)
        XCTAssertEqual(ClipboardRetentionPolicy.load(from: retentionURL), store.settings.retentionPolicy)

        let savedData = try Data(contentsOf: settingsURL)
        let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        XCTAssertEqual(savedJSON["panelPlacement"] as? String, "top")
        XCTAssertEqual(savedJSON["appearanceMode"] as? String, "dark")
        XCTAssertEqual(savedJSON["copyFeedbackSoundEnabled"] as? Bool, false)
        XCTAssertEqual(savedJSON["copyFeedbackAnimationEnabled"] as? Bool, false)
        XCTAssertEqual(savedJSON["autoPasteOnCardSelection"] as? Bool, true)
    }

    func testSettingsSaveUsesOwnerOnlyPermissions() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings").appendingPathComponent("app_settings.json")
        let retentionURL = tempDirectory.appendingPathComponent("settings").appendingPathComponent("retention_policy.json")
        let store = AppSettingsStore(
            settingsURL: settingsURL,
            retentionPolicyURL: retentionURL,
            appliesRetentionToSharedDatabase: false
        )

        XCTAssertTrue(store.save())

        XCTAssertEqual(try posixPermissions(at: settingsURL), AppPaths.ownerOnlyFilePermissions)
        XCTAssertEqual(try posixPermissions(at: retentionURL), AppPaths.ownerOnlyFilePermissions)
        XCTAssertEqual(try posixPermissions(at: settingsURL.deletingLastPathComponent()), AppPaths.ownerOnlyDirectoryPermissions)
    }

    func testLegacyGridListSettingsDecodeWithSafeDefaults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("app_settings.json")
        let legacyJSON = """
        {
          "historyLayout": "list",
          "panelHeight": 520,
          "fetchLimit": 240,
          "maxStoredItems": 600,
          "maxAgeDays": 45,
          "privateModeOnLaunch": true
        }
        """
        try legacyJSON.write(to: settingsURL, atomically: true, encoding: .utf8)

        let settings = AppSettings.load(from: settingsURL)

        XCTAssertEqual(settings.historyLayout, .list)
        XCTAssertEqual(settings.panelPlacement, .bottom)
        XCTAssertEqual(settings.panelSizePreset, .compact)
        XCTAssertEqual(settings.customPanelHeight, 520)
        XCTAssertEqual(settings.folderSidebarVisibility, .automatic)
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertTrue(settings.copyFeedbackSoundEnabled)
        XCTAssertTrue(settings.copyFeedbackAnimationEnabled)
        XCTAssertFalse(settings.autoPasteOnCardSelection)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(settings.fetchLimit, 240)
        XCTAssertEqual(settings.maxStoredItems, 600)
        XCTAssertEqual(settings.maxAgeDays, 45)
        XCTAssertTrue(settings.privateModeOnLaunch)
    }

    func testDefaultSettingsUseHorizontalCompactPanel() {
        let settings = AppSettings()

        XCTAssertEqual(settings.historyLayout, .horizontal)
        XCTAssertEqual(settings.panelPlacement, .bottom)
        XCTAssertEqual(settings.panelSizePreset, .compact)
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertTrue(settings.copyFeedbackSoundEnabled)
        XCTAssertTrue(settings.copyFeedbackAnimationEnabled)
        XCTAssertFalse(settings.autoPasteOnCardSelection)
        XCTAssertEqual(settings.fetchLimit, 40)
        XCTAssertEqual(settings.maxStoredItems, 100)
        XCTAssertEqual(settings.maxAgeDays, 14)
        XCTAssertFalse(settings.shouldShowFolderSidebar)
    }

    func testExistingSavedSettingsWithoutRetentionKeepRetentionDisabled() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("app_settings.json")
        let existingJSON = """
        {
          "historyLayout": "horizontal",
          "panelSizePreset": "compact",
          "customPanelWidth": 1040,
          "customPanelHeight": 340,
          "folderSidebarVisibility": "automatic",
          "launchAtLogin": false,
          "fetchLimit": 100,
          "privateModeOnLaunch": false
        }
        """
        try existingJSON.write(to: settingsURL, atomically: true, encoding: .utf8)

        let settings = AppSettings.load(from: settingsURL)

        XCTAssertEqual(settings.fetchLimit, 100)
        XCTAssertEqual(settings.panelPlacement, .bottom)
        XCTAssertNil(settings.maxStoredItems)
        XCTAssertNil(settings.maxAgeDays)
        XCTAssertEqual(settings.appearanceMode, .system)
        XCTAssertTrue(settings.copyFeedbackSoundEnabled)
        XCTAssertTrue(settings.copyFeedbackAnimationEnabled)
    }

    func testAppearanceAndFeedbackSettingsDecodeWhenPresent() throws {
        let json = """
        {
          "appearanceMode": "light",
          "copyFeedbackSoundEnabled": false,
          "copyFeedbackAnimationEnabled": false,
          "autoPasteOnCardSelection": true
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.appearanceMode, .light)
        XCTAssertFalse(settings.copyFeedbackSoundEnabled)
        XCTAssertFalse(settings.copyFeedbackAnimationEnabled)
        XCTAssertTrue(settings.autoPasteOnCardSelection)
    }

    func testMissingPanelPlacementDecodesAsBottom() throws {
        let json = """
        {
          "historyLayout": "grid",
          "panelSizePreset": "standard",
          "customPanelWidth": 1200,
          "customPanelHeight": 480
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.panelPlacement, .bottom)
    }

    func testMissingOrCorruptRetentionPolicyUsesNonDestructiveFallback() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let missingPolicy = ClipboardRetentionPolicy.load(
            from: tempDirectory.appendingPathComponent("missing_retention_policy.json")
        )

        XCTAssertEqual(missingPolicy.fetchLimit, AppSettings.defaultFetchLimit)
        XCTAssertNil(missingPolicy.maxStoredItems)
        XCTAssertNil(missingPolicy.maxAgeDays)

        let corruptPolicyURL = tempDirectory.appendingPathComponent("corrupt_retention_policy.json")
        try "{ not json".write(to: corruptPolicyURL, atomically: true, encoding: .utf8)

        let corruptPolicy = ClipboardRetentionPolicy.load(from: corruptPolicyURL)

        XCTAssertEqual(corruptPolicy.fetchLimit, AppSettings.defaultFetchLimit)
        XCTAssertNil(corruptPolicy.maxStoredItems)
        XCTAssertNil(corruptPolicy.maxAgeDays)
    }

    func testTopAndBottomPanelFramesUseFullWidthAndPresetHeight() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 1_600, height: 900)

        let bottomFrame = AppSettings(panelPlacement: .bottom, panelSizePreset: .compact)
            .panelFrame(for: visibleFrame)
        XCTAssertEqual(bottomFrame, CGRect(x: 116, y: 96, width: 1_568, height: 300))

        let topFrame = AppSettings(panelPlacement: .top, panelSizePreset: .standard)
            .panelFrame(for: visibleFrame)
        XCTAssertEqual(topFrame, CGRect(x: 116, y: 604, width: 1_568, height: 360))
    }

    func testLeftAndRightPanelFramesUseFullHeightAndPresetWidth() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 1_600, height: 900)

        let leftFrame = AppSettings(panelPlacement: .left, panelSizePreset: .compact)
            .panelFrame(for: visibleFrame)
        XCTAssertEqual(leftFrame, CGRect(x: 116, y: 96, width: 620, height: 868))

        let rightFrame = AppSettings(panelPlacement: .right, panelSizePreset: .large)
            .panelFrame(for: visibleFrame)
        XCTAssertEqual(rightFrame, CGRect(x: 824, y: 96, width: 860, height: 868))
    }

    func testCustomPanelFramesClampToVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 800, height: 500)

        let topFrame = AppSettings(
            panelPlacement: .top,
            panelSizePreset: .custom,
            customPanelWidth: 2_000,
            customPanelHeight: 900
        ).panelFrame(for: visibleFrame)
        XCTAssertEqual(topFrame, CGRect(x: 116, y: 96, width: 768, height: 468))

        let rightFrame = AppSettings(
            panelPlacement: .right,
            panelSizePreset: .custom,
            customPanelWidth: 2_000,
            customPanelHeight: 900
        ).panelFrame(for: visibleFrame)
        XCTAssertEqual(rightFrame, CGRect(x: 116, y: 96, width: 768, height: 468))
    }

    func testAllPanelPlacementsStayInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 1_600, height: 900)

        let settings = PanelPlacement.allCases.flatMap { placement in
            PanelSizePreset.allCases.map { preset in
                AppSettings(
                    panelPlacement: placement,
                    panelSizePreset: preset,
                    customPanelWidth: 2_400,
                    customPanelHeight: 1_200
                )
            }
        }

        for setting in settings {
            let frame = setting.panelFrame(for: visibleFrame)
            XCTAssertGreaterThanOrEqual(frame.minX, visibleFrame.minX)
            XCTAssertGreaterThanOrEqual(frame.minY, visibleFrame.minY)
            XCTAssertLessThanOrEqual(frame.maxX, visibleFrame.maxX)
            XCTAssertLessThanOrEqual(frame.maxY, visibleFrame.maxY)
        }
    }

    func testAutomaticSidebarShowsForVerticalOrLargerPanels() {
        XCTAssertFalse(AppSettings(historyLayout: .horizontal, panelSizePreset: .compact).shouldShowFolderSidebar)
        XCTAssertTrue(AppSettings(historyLayout: .grid, panelSizePreset: .compact).shouldShowFolderSidebar)
        XCTAssertTrue(AppSettings(historyLayout: .horizontal, panelSizePreset: .standard).shouldShowFolderSidebar)
        XCTAssertFalse(AppSettings(folderSidebarVisibility: .hidden).shouldShowFolderSidebar)
        XCTAssertTrue(AppSettings(folderSidebarVisibility: .always).shouldShowFolderSidebar)
    }

    func testCorruptedSettingsReturnSafeDefaults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("app_settings.json")
        try "{ not json".write(to: settingsURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(AppSettings.load(from: settingsURL), AppSettings())
    }

    func testSettingsStoreFallsBackToExistingRetentionPolicy() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("missing_settings.json")
        let retentionURL = tempDirectory.appendingPathComponent("retention_policy.json")
        let policy = ClipboardRetentionPolicy(fetchLimit: 80, maxStoredItems: 240, maxAgeDays: 14)
        let encoder = JSONEncoder()
        try encoder.encode(policy).write(to: retentionURL)

        let store = AppSettingsStore(
            settingsURL: settingsURL,
            retentionPolicyURL: retentionURL,
            appliesRetentionToSharedDatabase: false
        )

        XCTAssertEqual(store.settings.fetchLimit, 80)
        XCTAssertEqual(store.settings.maxStoredItems, 240)
        XCTAssertEqual(store.settings.maxAgeDays, 14)
    }

    func testSettingsStoreUsesNewStorageDefaultsWhenNoFilesExist() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = AppSettingsStore(
            settingsURL: tempDirectory.appendingPathComponent("missing_settings.json"),
            retentionPolicyURL: tempDirectory.appendingPathComponent("missing_retention_policy.json"),
            appliesRetentionToSharedDatabase: false
        )

        XCTAssertEqual(store.settings.fetchLimit, 40)
        XCTAssertEqual(store.settings.maxStoredItems, 100)
        XCTAssertEqual(store.settings.maxAgeDays, 14)
    }

    func testResetRestoresAppearanceAndFeedbackDefaults() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = AppSettingsStore(
            settingsURL: tempDirectory.appendingPathComponent("app_settings.json"),
            retentionPolicyURL: tempDirectory.appendingPathComponent("retention_policy.json"),
            appliesRetentionToSharedDatabase: false
        )
        store.settings.appearanceMode = .dark
        store.settings.copyFeedbackSoundEnabled = false
        store.settings.copyFeedbackAnimationEnabled = false

        store.resetToDefaults()

        XCTAssertEqual(store.settings.appearanceMode, .system)
        XCTAssertTrue(store.settings.copyFeedbackSoundEnabled)
        XCTAssertTrue(store.settings.copyFeedbackAnimationEnabled)
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        return permissions.intValue & 0o777
    }
}
#elseif canImport(Testing)
import Testing
@testable import Forkclip

@MainActor
struct AppSettingsTests {
    @Test
    func xctestCoverageSentinelAppSettingsTestsOnMacOS() async throws {
        #expect(true)
    }
}
#endif
