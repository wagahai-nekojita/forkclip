import SwiftUI
import AppKit

enum HostingViewFactory {
    @MainActor
    static func fixedPanelContentView<Content: View>(rootView: Content, frame: NSRect) -> NSView {
        let containerView = NSView(frame: frame)
        containerView.autoresizesSubviews = true

        let hostingView = fixedPanelHostingView(rootView: rootView)
        hostingView.frame = containerView.bounds
        containerView.addSubview(hostingView)

        return containerView
    }

    @MainActor
    static func fixedPanelHostingView<Content: View>(rootView: Content) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        configureFixedPanelHostingView(hostingView)
        return hostingView
    }

    @MainActor
    static func configureFixedPanelHostingView<Content: View>(_ hostingView: NSHostingView<Content>) {
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        if #available(macOS 13.3, *) {
            hostingView.safeAreaRegions = []
        }
    }
}
