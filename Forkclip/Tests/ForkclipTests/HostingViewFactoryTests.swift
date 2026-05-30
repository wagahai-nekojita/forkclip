import XCTest
import SwiftUI
@testable import Forkclip

@MainActor
final class HostingViewFactoryTests: XCTestCase {
    func testFixedPanelContentViewWrapsHostingViewInAppKitContainer() throws {
        let panelFrame = NSRect(x: 0, y: 0, width: 640, height: 300)
        let contentView = HostingViewFactory.fixedPanelContentView(rootView: Text("panel"), frame: panelFrame)

        XCTAssertEqual(contentView.frame, panelFrame)
        XCTAssertTrue(contentView.autoresizesSubviews)
        XCTAssertEqual(contentView.subviews.count, 1)

        let hostingView = try XCTUnwrap(contentView.subviews.first as? NSHostingView<Text>)
        XCTAssertEqual(hostingView.frame, contentView.bounds)
    }

    func testFixedPanelHostingViewDoesNotDriveWindowSizing() {
        let hostingView = HostingViewFactory.fixedPanelHostingView(rootView: Text("panel"))

        XCTAssertTrue(hostingView.translatesAutoresizingMaskIntoConstraints)
        XCTAssertTrue(hostingView.autoresizingMask.contains(.width))
        XCTAssertTrue(hostingView.autoresizingMask.contains(.height))

        if #available(macOS 13.0, *) {
            XCTAssertTrue(hostingView.sizingOptions.isEmpty)
        }
        if #available(macOS 13.3, *) {
            XCTAssertTrue(hostingView.safeAreaRegions.isEmpty)
        }
    }
}
