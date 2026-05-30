import Combine
import SwiftUI
import AppKit
import Darwin

final class QuickPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSPanel?
    var dashboardWindow: NSWindow?
    var settingsWindow: NSWindow?
    var aboutWindow: NSWindow?
    private var panelLocalMouseDownMonitor: Any?
    private var panelGlobalMouseDownMonitor: Any?
    private var appDeactivateObserver: NSObjectProtocol?
    let settingsStore = AppSettingsStore()
    private var cachedManager: ClipboardManager?
    var manager: ClipboardManager {
        if let cachedManager {
            return cachedManager
        }
        let store = DatabaseManager.shared
        let retentionPolicy = settingsStore.settings.retentionPolicy
        Task {
            await store.updateRetentionPolicy(retentionPolicy)
        }
        let manager = ClipboardManager(
            pasteboard: NSPasteboard.general,
            store: store,
            security: SecurityManager.shared,
            frontmostApplicationProvider: WorkspaceFrontmostApplicationProvider(),
            initialPrivateMode: settingsStore.settings.privateModeOnLaunch
        )
        cachedManager = manager
        return manager
    }
    private var settingsCancellable: AnyCancellable?
    private lazy var feedbackController = ClipboardFeedbackController { [weak self] in
        self?.statusItem?.button
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.app.notice("Application did finish launching.")
        applyAppearance(settingsStore.settings.appearanceMode)
        setupStatusItem()
        setupWindow()
        configureClipboardFeedback()
        if ProcessInfo.processInfo.environment["FORKCLIP_NATIVE_SMOKE_REPORT"] != nil {
            Task { await runNativeSmokeIfRequested() }
            return
        }
        manager.startMonitoring()
        AppLogger.app.notice("Clipboard monitoring start requested from AppDelegate.")
        observeSettingsChanges()
        AppLogger.app.notice("Application launch setup completed.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopPanelDismissMonitors()
        manager.stopMonitoring()
    }

    @MainActor
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = statusBarIcon()
            button.imagePosition = .imageOnly
            button.wantsLayer = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @MainActor
    private func statusBarIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "AppMenuIconTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }

        return NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: AppInfo.displayName) ?? NSImage()
    }

    @MainActor
    func showStatusItemMenu(with event: NSEvent) {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let dashboardItem = NSMenuItem(title: "Dashboard を開く", action: #selector(showDashboardWindow(_:)), keyEquivalent: "")
        dashboardItem.target = self
        menu.addItem(dashboardItem)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "\(AppInfo.displayName) について", action: #selector(showAboutWindow(_:)), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        let settingsItem = NSMenuItem(title: "設定...", action: #selector(showSettingsWindow(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "\(AppInfo.displayName) を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @MainActor
    func setupWindow() {
        let contentView = ForkclipView(
            manager: manager,
            settingsStore: settingsStore,
            openDashboard: { [weak self] in
                Task { @MainActor in
                    self?.showDashboardWindow(nil)
                }
            },
            openSettings: { [weak self] in
                Task { @MainActor in
                    self?.showSettingsWindow(nil)
                }
            },
            openAbout: { [weak self] in
                Task { @MainActor in
                    self?.showAboutWindow(nil)
                }
            }
        )
            .edgesIgnoringSafeArea(.all)

        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        let panelFrame = panelFrame(for: screen)
        window = QuickPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: panelFrame.width, height: panelFrame.height),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window?.isFloatingPanel = true
        window?.level = .mainMenu
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.backgroundColor = .clear
        window?.isOpaque = false
        window?.hasShadow = true
        window?.contentView = HostingViewFactory.fixedPanelContentView(
            rootView: contentView,
            frame: NSRect(origin: .zero, size: panelFrame.size)
        )
        positionWindow()
    }

    @MainActor
    private func observeSettingsChanges() {
        settingsCancellable = settingsStore.$settings
            .dropFirst()
            .sink { [weak self] settings in
                Task { @MainActor in
                    self?.applyAppearance(settings.appearanceMode)
                    self?.positionWindow()
                }
            }
    }

    @MainActor
    private func applyAppearance(_ mode: AppAppearanceMode) {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @MainActor
    private func configureClipboardFeedback() {
        manager.feedbackHandler = { [weak self] _ in
            guard let self else { return }
            self.feedbackController.emit(settings: self.settingsStore.settings)
        }
    }

    @MainActor
    private func runNativeSmokeIfRequested() async {
        guard let reportPath = ProcessInfo.processInfo.environment["FORKCLIP_NATIVE_SMOKE_REPORT"] else {
            return
        }

        var checks: [(String, Bool, String)] = []

        func record(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append((name, passed, detail))
        }

        for mode in AppAppearanceMode.allCases {
            applyAppearance(mode)
            let appearanceName = NSApp.appearance?.name
            let passed: Bool
            let expected: String
            switch mode {
            case .system:
                passed = appearanceName == nil
                expected = "nil"
            case .light:
                passed = appearanceName == .aqua
                expected = NSAppearance.Name.aqua.rawValue
            case .dark:
                passed = appearanceName == .darkAqua
                expected = NSAppearance.Name.darkAqua.rawValue
            }
            record(
                "appearance.\(mode.rawValue)",
                passed,
                "expected=\(expected) actual=\(appearanceName?.rawValue ?? "nil")"
            )
        }

        let menuIcon = statusItem?.button?.image
        record(
            "menuIcon.usesOriginalColors",
            menuIcon?.isTemplate == false,
            "isTemplate=\(menuIcon?.isTemplate.description ?? "nil")"
        )
        record(
            "menuIcon.displaySize",
            menuIcon?.size == NSSize(width: 18, height: 18),
            "size=\(menuIcon?.size.debugDescription ?? "nil")"
        )
        record(
            "asset.menuIcon",
            Bundle.main.url(forResource: "AppMenuIconTemplate", withExtension: "png") != nil
        )
        record(
            "asset.feedbackSound",
            Bundle.main.url(forResource: "ClipboardFeedbackClick", withExtension: "wav") != nil
        )

        let disabledEmission = feedbackController.emit(
            settings: AppSettings(copyFeedbackSoundEnabled: false, copyFeedbackAnimationEnabled: false)
        )
        record(
            "feedback.disabledChannels",
            !disabledEmission.soundEnabled
                && !disabledEmission.soundAssetLoaded
                && !disabledEmission.animationEnabled
                && !disabledEmission.animationStarted,
            "soundAssetLoaded=\(disabledEmission.soundAssetLoaded) animationStarted=\(disabledEmission.animationStarted)"
        )

        let enabledEmission = feedbackController.emit(
            settings: AppSettings(copyFeedbackSoundEnabled: true, copyFeedbackAnimationEnabled: true)
        )
        record(
            "feedback.enabledSoundAsset",
            enabledEmission.soundEnabled && enabledEmission.soundAssetLoaded,
            "soundPlayed=\(enabledEmission.soundPlayed)"
        )
        record(
            "feedback.enabledAnimation",
            enabledEmission.animationEnabled
                && enabledEmission.statusButtonAvailable
                && (enabledEmission.reduceMotionEnabled || enabledEmission.animationStarted),
            "reduceMotion=\(enabledEmission.reduceMotionEnabled) animationStarted=\(enabledEmission.animationStarted)"
        )

        var appCopyEnabledEmission: ClipboardFeedbackEmission?
        settingsStore.settings.copyFeedbackSoundEnabled = true
        settingsStore.settings.copyFeedbackAnimationEnabled = true
        manager.feedbackHandler = { [weak self] _ in
            guard let self else { return }
            appCopyEnabledEmission = self.feedbackController.emit(settings: self.settingsStore.settings)
        }
        await manager.copyToClipboard(ClipboardItem(id: UUID(), content: "forkclip-native-smoke-copy-enabled", timestamp: Date()))
        record(
            "appCopy.enabledFeedback",
            appCopyEnabledEmission?.soundEnabled == true
                && appCopyEnabledEmission?.soundAssetLoaded == true
                && appCopyEnabledEmission?.animationEnabled == true
                && appCopyEnabledEmission?.statusButtonAvailable == true
                && (appCopyEnabledEmission?.reduceMotionEnabled == true || appCopyEnabledEmission?.animationStarted == true),
            "emission=\(String(describing: appCopyEnabledEmission))"
        )

        var appCopyDisabledEmission: ClipboardFeedbackEmission?
        settingsStore.settings.copyFeedbackSoundEnabled = false
        settingsStore.settings.copyFeedbackAnimationEnabled = false
        manager.feedbackHandler = { [weak self] _ in
            guard let self else { return }
            appCopyDisabledEmission = self.feedbackController.emit(settings: self.settingsStore.settings)
        }
        await manager.copyToClipboard(ClipboardItem(id: UUID(), content: "forkclip-native-smoke-copy-disabled", timestamp: Date()))
        record(
            "appCopy.disabledFeedback",
            appCopyDisabledEmission?.soundEnabled == false
                && appCopyDisabledEmission?.animationEnabled == false
                && appCopyDisabledEmission?.soundAssetLoaded == false
                && appCopyDisabledEmission?.animationStarted == false,
            "emission=\(String(describing: appCopyDisabledEmission))"
        )

        for check in await runMultiformatNativeSmokeChecks() {
            record(check.name, check.passed, check.detail)
        }

        let failedChecks = checks.filter { !$0.1 }
        let reportLines = [
            "nativeSmokeStatus=\(failedChecks.isEmpty ? "passed" : "failed")"
        ] + checks.map { name, passed, detail in
            "check \(passed ? "passed" : "failed") \(name)\(detail.isEmpty ? "" : " \(detail)")"
        }
        do {
            try reportLines.joined(separator: "\n").write(
                toFile: reportPath,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            fputs("Failed to write native smoke report: \(error)\n", stderr)
            exit(1)
        }

        exit(failedChecks.isEmpty ? 0 : 1)
    }

    @MainActor
    private func runMultiformatNativeSmokeChecks() async -> [(name: String, passed: Bool, detail: String)] {
        do {
            let tempDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("forkclip-native-smoke-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDirectory) }

            let store = DatabaseManager(
                databaseURL: tempDirectory.appendingPathComponent("forkclip.sqlite"),
                retentionPolicy: ClipboardRetentionPolicy(fetchLimit: 20)
            )
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("ForkclipNativeSmoke-\(UUID().uuidString)"))
            let smokeManager = ClipboardManager(
                pasteboard: pasteboard,
                store: store,
                security: SecurityManager.shared,
                frontmostApplicationProvider: WorkspaceFrontmostApplicationProvider(),
                initialPrivateMode: false
            )
            await smokeManager.waitForInitialLoadForTests()

            func runCase(
                _ name: String,
                seed: () -> Void,
                verify: (ClipboardItem) -> Bool
            ) async -> (name: String, passed: Bool, detail: String) {
                pasteboard.clearContents()
                seed()
                await smokeManager.handleNewClipboardItem(changeCount: pasteboard.changeCount)
                guard let item = smokeManager.items.first else {
                    return (name, false, "item=nil status=\(ClipboardStatusFormatter.operationText(smokeManager.diagnostics.lastSaveStatus))")
                }
                let payloadTypes = (await store.payloads(for: item.id)).map(\.contentType.rawValue).joined(separator: ",")
                await smokeManager.copyToClipboard(item)
                return (name, verify(item), "item=\(item.content) primary=\(item.primaryContentType.rawValue) payloads=\(payloadTypes)")
            }

            let imageData = Data([0x89, 0x50, 0x4E, 0x47])
            let fileURL = "file:///Users/example/Documents/report.pdf"
            let rtfData = Data("{\\rtf1 native}".utf8)
            let htmlData = Data("<p>native</p>".utf8)
            let urlText = "https://example.com/native-smoke"

            var results: [(name: String, passed: Bool, detail: String)] = []
            results.append(await runCase("multiformat.image") {
                    _ = pasteboard.setData(imageData, forType: .png)
                } verify: { item in
                    item.content == "画像"
                        && item.primaryContentType == .image
                        && pasteboard.data(forType: .png) == imageData
                })
            results.append(await runCase("multiformat.fileURL") {
                    _ = pasteboard.setString(fileURL, forType: .fileURL)
                } verify: { item in
                    item.content == "ファイル: report.pdf"
                        && item.primaryContentType == .fileURL
                        && pasteboard.string(forType: .fileURL) == fileURL
                })
            results.append(await runCase("multiformat.mixedImageFileURL") {
                    _ = pasteboard.setString(fileURL, forType: .fileURL)
                    _ = pasteboard.setData(imageData, forType: .png)
                } verify: { item in
                    item.content == "画像"
                        && item.primaryContentType == .image
                        && pasteboard.data(forType: .png) == imageData
                        && pasteboard.string(forType: .fileURL) == fileURL
                })
            let mixedPayloadTypes = (await store.payloads(for: smokeManager.items.first?.id ?? UUID())).map(\.contentType)
            if let index = results.firstIndex(where: { $0.name == "multiformat.mixedImageFileURL" }) {
                let result = results[index]
                results[index] = (
                    result.name,
                    result.passed && mixedPayloadTypes == [.image, .fileURL],
                    "\(result.detail) mixedPayloads=\(mixedPayloadTypes.map(\.rawValue).joined(separator: ","))"
                )
            }
            results.append(await runCase("multiformat.richTextHTML") {
                    _ = pasteboard.setData(rtfData, forType: .rtf)
                    _ = pasteboard.setData(htmlData, forType: .html)
                    _ = pasteboard.setString("native rich", forType: .string)
                } verify: { item in
                    item.content == "native rich"
                        && item.primaryContentType == .rtf
                        && pasteboard.data(forType: .rtf) == rtfData
                        && pasteboard.data(forType: .html) == htmlData
                        && pasteboard.string(forType: .string) == "native rich"
                })
            results.append(await runCase("multiformat.urlText") {
                    _ = pasteboard.setString(urlText, forType: .URL)
                    _ = pasteboard.setString(urlText, forType: .string)
                } verify: { item in
                    item.content == urlText
                        && item.primaryContentType == .urlText
                        && pasteboard.string(forType: .URL) == urlText
                        && pasteboard.string(forType: .string) == urlText
                })
            results.append(await runCase("multiformat.plainText") {
                    _ = pasteboard.setString("plain native smoke", forType: .string)
                } verify: { item in
                    item.content == "plain native smoke"
                        && item.primaryContentType == .plainText
                        && pasteboard.string(forType: .string) == "plain native smoke"
                })
            return results
        } catch {
            return [("multiformat.setup", false, String(describing: error))]
        }
    }

    @MainActor
    private func panelFrame(for screen: NSScreen?) -> NSRect {
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_040, height: 720)
        return settingsStore.settings.panelFrame(for: visibleFrame)
    }

    @MainActor
    private func positionWindow() {
        guard let window else { return }
        let screen = statusItem?.button?.window?.screen ?? NSScreen.main
        guard let screen else { return }

        window.setFrame(panelFrame(for: screen), display: false)
    }

    @objc @MainActor
    func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp, let event = NSApp.currentEvent {
            showStatusItemMenu(with: event)
        } else {
            toggleWindow()
        }
    }

    @objc @MainActor
    func toggleWindow() {
        if window?.isVisible == true {
            hideMainPanel()
        } else {
            showMainPanel()
        }
    }

    @MainActor
    private func showMainPanel() {
        manager.captureAutoPasteTarget()
        positionWindow()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startPanelDismissMonitors()
    }

    @MainActor
    private func hideMainPanel() {
        window?.orderOut(nil)
        stopPanelDismissMonitors()
    }

    @MainActor
    private func startPanelDismissMonitors() {
        stopPanelDismissMonitors()

        let mouseDownEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        panelLocalMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
            self?.dismissMainPanelIfNeeded(for: event)
            return event
        }
        panelGlobalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownEvents) { [weak self] _ in
            Task { @MainActor in
                self?.dismissMainPanelForGlobalMouseDown()
            }
        }
        appDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissMainPanelForGlobalMouseDown()
            }
        }
    }

    @MainActor
    private func stopPanelDismissMonitors() {
        if let panelLocalMouseDownMonitor {
            NSEvent.removeMonitor(panelLocalMouseDownMonitor)
            self.panelLocalMouseDownMonitor = nil
        }

        if let panelGlobalMouseDownMonitor {
            NSEvent.removeMonitor(panelGlobalMouseDownMonitor)
            self.panelGlobalMouseDownMonitor = nil
        }

        if let appDeactivateObserver {
            NotificationCenter.default.removeObserver(appDeactivateObserver)
            self.appDeactivateObserver = nil
        }
    }

    @MainActor
    private func dismissMainPanelIfNeeded(for event: NSEvent) {
        guard window?.isVisible == true else {
            stopPanelDismissMonitors()
            return
        }

        if isEventInMainPanel(event) || isEventInStatusItem(event) {
            return
        }

        hideMainPanel()
    }

    @MainActor
    private func dismissMainPanelForGlobalMouseDown() {
        guard window?.isVisible == true else {
            stopPanelDismissMonitors()
            return
        }

        hideMainPanel()
    }

    @MainActor
    private func isEventInMainPanel(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        guard let eventWindow = event.window else { return false }
        return eventWindow === window
            || eventWindow.sheetParent === window
            || window.attachedSheet === eventWindow
    }

    @MainActor
    private func isEventInStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button,
              let buttonWindow = button.window,
              event.window === buttonWindow else {
            return false
        }

        let pointInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(pointInButton)
    }

    @objc @MainActor
    func showDashboardWindow(_ sender: Any?) {
        if dashboardWindow == nil {
            let dashboardView = DashboardView(
                manager: manager,
                settingsStore: settingsStore,
                openSettings: { [weak self] in
                    Task { @MainActor in
                        self?.showSettingsWindow(nil)
                    }
                },
                openAbout: { [weak self] in
                    Task { @MainActor in
                        self?.showAboutWindow(nil)
                    }
                }
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_280, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "\(AppInfo.displayName) Dashboard"
            window.minSize = NSSize(width: 1_060, height: 620)
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: dashboardView)
            window.isReleasedWhenClosed = false
            window.center()
            dashboardWindow = window
        }

        if window?.isVisible == true {
            hideMainPanel()
        }

        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    @objc @MainActor
    func showSettingsWindow(_ sender: Any?) {
        if settingsWindow == nil {
            let settingsView = SettingsView(settingsStore: settingsStore)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "\(AppInfo.displayName) 設定"
            window.minSize = NSSize(width: 760, height: 540)
            window.contentView = NSHostingView(rootView: settingsView)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        if window?.isVisible == true {
            hideMainPanel()
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc @MainActor
    func showAboutWindow(_ sender: Any?) {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "\(AppInfo.displayName) について"
            window.contentView = NSHostingView(rootView: aboutView)
            window.isReleasedWhenClosed = false
            window.center()
            aboutWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
}
