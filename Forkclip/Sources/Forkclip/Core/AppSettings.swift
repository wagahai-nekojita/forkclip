import Combine
import CoreGraphics
import Foundation

enum HistoryLayout: String, Codable, CaseIterable, Identifiable {
    case horizontal
    case grid
    case list

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontal:
            return "Horizontal"
        case .grid:
            return "Grid"
        case .list:
            return "List"
        }
    }

    var toolbarDisplayName: String {
        switch self {
        case .horizontal:
            return "Horz"
        case .grid:
            return "Grid"
        case .list:
            return "List"
        }
    }
}

enum PanelSizePreset: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case large
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .standard:
            return "Standard"
        case .large:
            return "Large"
        case .custom:
            return "Custom"
        }
    }
}

enum PanelPlacement: String, Codable, CaseIterable, Identifiable {
    case bottom
    case top
    case left
    case right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottom:
            return "Bottom"
        case .top:
            return "Top"
        case .left:
            return "Left"
        case .right:
            return "Right"
        }
    }
}

enum FolderSidebarVisibility: String, Codable, CaseIterable, Identifiable {
    case automatic
    case always
    case hidden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .always:
            return "Always"
        case .hidden:
            return "Hidden"
        }
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

struct AppSettings: Codable, Equatable {
    static let defaultFetchLimit = 40
    static let defaultMaxStoredItems = 100
    static let defaultMaxAgeDays = 14
    static let defaultCustomPanelWidth: Double = 1040
    static let defaultCustomPanelHeight: Double = 340
    static let minimumPanelWidth: Double = 320
    static let minimumCustomPanelWidth: Double = 720
    static let minimumPanelHeight: Double = 220
    static let maximumPanelHeight: Double = 720
    static let panelEdgeInset: Double = 16
    static let horizontalScreenInset: Double = panelEdgeInset * 2
    static let verticalScreenInset: Double = panelEdgeInset * 2

    var historyLayout: HistoryLayout
    var panelPlacement: PanelPlacement
    var panelSizePreset: PanelSizePreset
    var customPanelWidth: Double
    var customPanelHeight: Double
    var folderSidebarVisibility: FolderSidebarVisibility
    var appearanceMode: AppAppearanceMode
    var copyFeedbackSoundEnabled: Bool
    var copyFeedbackAnimationEnabled: Bool
    var autoPasteOnCardSelection: Bool
    var launchAtLogin: Bool
    var fetchLimit: Int
    var maxStoredItems: Int?
    var maxAgeDays: Int?
    var privateModeOnLaunch: Bool

    init(
        historyLayout: HistoryLayout = .horizontal,
        panelPlacement: PanelPlacement = .bottom,
        panelSizePreset: PanelSizePreset = .compact,
        customPanelWidth: Double = AppSettings.defaultCustomPanelWidth,
        customPanelHeight: Double = AppSettings.defaultCustomPanelHeight,
        folderSidebarVisibility: FolderSidebarVisibility = .automatic,
        appearanceMode: AppAppearanceMode = .system,
        copyFeedbackSoundEnabled: Bool = true,
        copyFeedbackAnimationEnabled: Bool = true,
        autoPasteOnCardSelection: Bool = false,
        launchAtLogin: Bool = false,
        fetchLimit: Int = AppSettings.defaultFetchLimit,
        maxStoredItems: Int? = AppSettings.defaultMaxStoredItems,
        maxAgeDays: Int? = AppSettings.defaultMaxAgeDays,
        privateModeOnLaunch: Bool = false
    ) {
        self.historyLayout = historyLayout
        self.panelPlacement = panelPlacement
        self.panelSizePreset = panelSizePreset
        self.customPanelWidth = max(Self.minimumCustomPanelWidth, customPanelWidth)
        self.customPanelHeight = min(max(customPanelHeight, Self.minimumPanelHeight), Self.maximumPanelHeight)
        self.folderSidebarVisibility = folderSidebarVisibility
        self.appearanceMode = appearanceMode
        self.copyFeedbackSoundEnabled = copyFeedbackSoundEnabled
        self.copyFeedbackAnimationEnabled = copyFeedbackAnimationEnabled
        self.autoPasteOnCardSelection = autoPasteOnCardSelection
        self.launchAtLogin = launchAtLogin
        self.fetchLimit = max(1, fetchLimit)
        self.maxStoredItems = maxStoredItems.map { max(1, $0) }
        self.maxAgeDays = maxAgeDays.map { max(1, $0) }
        self.privateModeOnLaunch = privateModeOnLaunch
    }

    enum CodingKeys: String, CodingKey {
        case historyLayout
        case panelPlacement
        case panelSizePreset
        case customPanelWidth
        case customPanelHeight
        case folderSidebarVisibility
        case appearanceMode
        case copyFeedbackSoundEnabled
        case copyFeedbackAnimationEnabled
        case autoPasteOnCardSelection
        case launchAtLogin
        case fetchLimit
        case maxStoredItems
        case maxAgeDays
        case privateModeOnLaunch
        case panelHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyPanelHeight = try container.decodeIfPresent(Double.self, forKey: .panelHeight)
        self.init(
            historyLayout: try container.decodeIfPresent(HistoryLayout.self, forKey: .historyLayout) ?? .horizontal,
            panelPlacement: try container.decodeIfPresent(PanelPlacement.self, forKey: .panelPlacement) ?? .bottom,
            panelSizePreset: try container.decodeIfPresent(PanelSizePreset.self, forKey: .panelSizePreset) ?? .compact,
            customPanelWidth: try container.decodeIfPresent(Double.self, forKey: .customPanelWidth) ?? Self.defaultCustomPanelWidth,
            customPanelHeight: try container.decodeIfPresent(Double.self, forKey: .customPanelHeight) ?? legacyPanelHeight ?? Self.defaultCustomPanelHeight,
            folderSidebarVisibility: try container.decodeIfPresent(FolderSidebarVisibility.self, forKey: .folderSidebarVisibility) ?? .automatic,
            appearanceMode: try container.decodeIfPresent(AppAppearanceMode.self, forKey: .appearanceMode) ?? .system,
            copyFeedbackSoundEnabled: try container.decodeIfPresent(Bool.self, forKey: .copyFeedbackSoundEnabled) ?? true,
            copyFeedbackAnimationEnabled: try container.decodeIfPresent(Bool.self, forKey: .copyFeedbackAnimationEnabled) ?? true,
            autoPasteOnCardSelection: try container.decodeIfPresent(Bool.self, forKey: .autoPasteOnCardSelection) ?? false,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            fetchLimit: try container.decodeIfPresent(Int.self, forKey: .fetchLimit) ?? Self.defaultFetchLimit,
            maxStoredItems: try container.decodeIfPresent(Int.self, forKey: .maxStoredItems),
            maxAgeDays: try container.decodeIfPresent(Int.self, forKey: .maxAgeDays),
            privateModeOnLaunch: try container.decodeIfPresent(Bool.self, forKey: .privateModeOnLaunch) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(historyLayout, forKey: .historyLayout)
        try container.encode(panelPlacement, forKey: .panelPlacement)
        try container.encode(panelSizePreset, forKey: .panelSizePreset)
        try container.encode(customPanelWidth, forKey: .customPanelWidth)
        try container.encode(customPanelHeight, forKey: .customPanelHeight)
        try container.encode(folderSidebarVisibility, forKey: .folderSidebarVisibility)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(copyFeedbackSoundEnabled, forKey: .copyFeedbackSoundEnabled)
        try container.encode(copyFeedbackAnimationEnabled, forKey: .copyFeedbackAnimationEnabled)
        try container.encode(autoPasteOnCardSelection, forKey: .autoPasteOnCardSelection)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(fetchLimit, forKey: .fetchLimit)
        try container.encodeIfPresent(maxStoredItems, forKey: .maxStoredItems)
        try container.encodeIfPresent(maxAgeDays, forKey: .maxAgeDays)
        try container.encode(privateModeOnLaunch, forKey: .privateModeOnLaunch)
    }

    var retentionPolicy: ClipboardRetentionPolicy {
        ClipboardRetentionPolicy(
            fetchLimit: fetchLimit,
            maxStoredItems: maxStoredItems,
            maxAgeDays: maxAgeDays
        )
    }

    var shouldShowFolderSidebar: Bool {
        switch folderSidebarVisibility {
        case .always:
            return true
        case .hidden:
            return false
        case .automatic:
            return !(historyLayout == .horizontal && panelSizePreset == .compact)
        }
    }

    func effectivePanelSize(for visibleSize: CGSize) -> CGSize {
        panelFrame(for: CGRect(origin: .zero, size: visibleSize)).size
    }

    func panelFrame(for visibleFrame: CGRect) -> CGRect {
        let horizontalInset = Self.edgeInset(for: Double(visibleFrame.width))
        let verticalInset = Self.edgeInset(for: Double(visibleFrame.height))
        let usableWidth = max(1, Double(visibleFrame.width) - (horizontalInset * 2))
        let usableHeight = max(1, Double(visibleFrame.height) - (verticalInset * 2))

        let width: Double
        let height: Double
        switch panelPlacement {
        case .bottom, .top:
            width = usableWidth
            height = Self.clamp(topBottomHeight, minimum: 1, maximum: usableHeight)
        case .left, .right:
            width = Self.clamp(leftRightWidth, minimum: 1, maximum: usableWidth)
            height = usableHeight
        }

        let x: Double
        switch panelPlacement {
        case .bottom, .top, .left:
            x = Double(visibleFrame.minX) + horizontalInset
        case .right:
            x = Double(visibleFrame.maxX) - horizontalInset - width
        }

        let y: Double
        switch panelPlacement {
        case .bottom, .left, .right:
            y = Double(visibleFrame.minY) + verticalInset
        case .top:
            y = Double(visibleFrame.maxY) - verticalInset - height
        }

        return CGRect(
            x: CGFloat(x),
            y: CGFloat(y),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }

    private var topBottomHeight: Double {
        switch panelSizePreset {
        case .compact:
            return 300
        case .standard:
            return 360
        case .large:
            return 440
        case .custom:
            return min(max(customPanelHeight, Self.minimumPanelHeight), Self.maximumPanelHeight)
        }
    }

    private var leftRightWidth: Double {
        switch panelSizePreset {
        case .compact:
            return 620
        case .standard:
            return 720
        case .large:
            return 860
        case .custom:
            return max(customPanelWidth, Self.minimumCustomPanelWidth)
        }
    }

    private static func edgeInset(for dimension: Double) -> Double {
        dimension > panelEdgeInset * 2 ? panelEdgeInset : 0
    }

    private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        let resolvedMaximum = max(1, maximum)
        let resolvedMinimum = min(max(1, minimum), resolvedMaximum)
        return min(max(value, resolvedMinimum), resolvedMaximum)
    }

    static func load(from url: URL? = nil) -> AppSettings {
        let settingsURL = url ?? (try? AppPaths.appSettingsURL())
        guard let settingsURL, FileManager.default.fileExists(atPath: settingsURL.path) else {
            return AppSettings()
        }

        do {
            let data = try Data(contentsOf: settingsURL)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            AppLogger.app.error("Failed to load app settings: \(String(describing: error), privacy: .public)")
            return AppSettings()
        }
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings

    private let settingsURL: URL?
    private let retentionPolicyURL: URL?
    private let appliesRetentionToSharedDatabase: Bool

    init(settingsURL: URL? = nil, retentionPolicyURL: URL? = nil, appliesRetentionToSharedDatabase: Bool = true) {
        self.settingsURL = settingsURL
        self.retentionPolicyURL = retentionPolicyURL
        self.appliesRetentionToSharedDatabase = appliesRetentionToSharedDatabase
        if let resolvedSettingsURL = settingsURL ?? (try? AppPaths.appSettingsURL()),
           FileManager.default.fileExists(atPath: resolvedSettingsURL.path) {
            self.settings = AppSettings.load(from: resolvedSettingsURL)
        } else if let resolvedRetentionPolicyURL = retentionPolicyURL ?? (try? AppPaths.retentionPolicyURL()),
                  FileManager.default.fileExists(atPath: resolvedRetentionPolicyURL.path) {
            let policy = ClipboardRetentionPolicy.load(from: resolvedRetentionPolicyURL)
            self.settings = AppSettings(
                fetchLimit: policy.fetchLimit,
                maxStoredItems: policy.maxStoredItems,
                maxAgeDays: policy.maxAgeDays
            )
        } else {
            self.settings = AppSettings()
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let settingsData = try encoder.encode(settings)
            let resolvedSettingsURL = try settingsURL ?? AppPaths.appSettingsURL()
            try AppPaths.createOwnerOnlyDirectory(at: resolvedSettingsURL.deletingLastPathComponent())
            try settingsData.write(to: resolvedSettingsURL, options: .atomic)
            try AppPaths.applyOwnerOnlyFilePermissions(to: resolvedSettingsURL)

            let retentionData = try encoder.encode(settings.retentionPolicy)
            let resolvedRetentionURL = try retentionPolicyURL ?? AppPaths.retentionPolicyURL()
            try AppPaths.createOwnerOnlyDirectory(at: resolvedRetentionURL.deletingLastPathComponent())
            try retentionData.write(to: resolvedRetentionURL, options: .atomic)
            try AppPaths.applyOwnerOnlyFilePermissions(to: resolvedRetentionURL)
            if appliesRetentionToSharedDatabase {
                let retentionPolicy = settings.retentionPolicy
                Task {
                    await DatabaseManager.shared.updateRetentionPolicy(retentionPolicy)
                }
            }
            return true
        } catch {
            AppLogger.app.error("Failed to save app settings: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func resetToDefaults() {
        settings = AppSettings()
        _ = save()
    }
}
