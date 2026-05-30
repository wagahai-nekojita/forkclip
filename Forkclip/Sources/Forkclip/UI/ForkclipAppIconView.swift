import AppKit
import SwiftUI

struct ForkclipAppIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "clipboard.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(AppInfo.displayName)
    }

    private var appIcon: NSImage? {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
