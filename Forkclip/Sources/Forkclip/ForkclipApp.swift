import SwiftUI

@main
struct ForkclipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                settingsStore: appDelegate.settingsStore,
                hotKeyController: appDelegate.hotKeyController
            )
        }
    }
}
