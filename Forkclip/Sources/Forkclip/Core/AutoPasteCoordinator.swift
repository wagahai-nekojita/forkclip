import AppKit
import CoreGraphics
import Foundation

struct AutoPasteTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?

    var displayName: String {
        localizedName ?? bundleIdentifier ?? "前面のアプリ"
    }
}

@MainActor
protocol AutoPasteCoordinating: AnyObject {
    func captureTarget() -> AutoPasteTarget?
    func paste(to target: AutoPasteTarget) async -> Bool
}

@MainActor
final class WorkspaceAutoPasteCoordinator: AutoPasteCoordinating {
    private let ownBundleIdentifier: String?

    init(ownBundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    func captureTarget() -> AutoPasteTarget? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.bundleIdentifier != ownBundleIdentifier else {
            return nil
        }
        return AutoPasteTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName
        )
    }

    func paste(to target: AutoPasteTarget) async -> Bool {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier),
              application.bundleIdentifier != ownBundleIdentifier else {
            return false
        }

        let didActivate = application.activate(options: [.activateIgnoringOtherApps])
        guard didActivate else { return false }

        try? await Task.sleep(nanoseconds: 120_000_000)
        return sendPasteShortcut()
    }

    private func sendPasteShortcut() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
