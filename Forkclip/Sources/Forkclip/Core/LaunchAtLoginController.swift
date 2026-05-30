import Combine
import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case unsupported
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
    case error(String)

    var isConfiguredOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .unsupported, .notRegistered, .notFound, .error:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .unsupported:
            return "Unsupported on this macOS version."
        case .notRegistered:
            return "Off"
        case .enabled:
            return "On"
        case .requiresApproval:
            return "Requires approval in System Settings."
        case .notFound:
            return "App service not found."
        case .error(let message):
            return message
        }
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState = .unsupported

    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    func refresh() {
        guard isSupported else {
            state = .unsupported
            return
        }

        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .notRegistered:
                state = .notRegistered
            case .enabled:
                state = .enabled
            case .requiresApproval:
                state = .requiresApproval
            case .notFound:
                state = .notFound
            @unknown default:
                state = .error("Unknown login item status.")
            }
        }
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else {
            state = .unsupported
            return false
        }

        do {
            if #available(macOS 13.0, *) {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                refresh()
                return true
            }
        } catch {
            state = .error("Login item update failed: \(error.localizedDescription)")
            return false
        }

        state = .unsupported
        return false
    }

    func openSystemSettingsLoginItems() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
