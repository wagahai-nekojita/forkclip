import AppKit
import CoreGraphics
import Foundation

struct AutoPasteTarget: Equatable, Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let launchDate: Date?

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        launchDate: Date? = nil
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.launchDate = launchDate
    }

    var displayName: String {
        localizedName ?? bundleIdentifier ?? "前面のアプリ"
    }

    func matches(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        launchDate: Date?
    ) -> Bool {
        guard self.processIdentifier == processIdentifier,
              let expectedBundleIdentifier = self.bundleIdentifier,
              let bundleIdentifier,
              expectedBundleIdentifier == bundleIdentifier,
              let expectedLaunchDate = self.launchDate,
              let launchDate else {
            return false
        }
        return expectedLaunchDate == launchDate
    }

    func matches(_ application: NSRunningApplication) -> Bool {
        matches(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            launchDate: application.launchDate
        )
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
              let bundleIdentifier = application.bundleIdentifier,
              bundleIdentifier != ownBundleIdentifier,
              application.launchDate != nil else {
            return nil
        }
        return AutoPasteTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            localizedName: application.localizedName,
            launchDate: application.launchDate
        )
    }

    func paste(to target: AutoPasteTarget) async -> Bool {
        guard let application = NSRunningApplication(processIdentifier: target.processIdentifier),
              application.bundleIdentifier != ownBundleIdentifier,
              target.matches(application) else {
            return false
        }

        let didActivate = application.activate(options: [.activateIgnoringOtherApps])
        guard didActivate else { return false }

        try? await Task.sleep(nanoseconds: 120_000_000)
        guard let currentFrontmost = NSWorkspace.shared.frontmostApplication,
              currentFrontmost.bundleIdentifier != ownBundleIdentifier,
              target.matches(currentFrontmost) else {
            return false
        }
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
