import AppKit
import SwiftUI

@MainActor
struct HorizontalWheelScrollBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> HorizontalWheelBridgeView {
        HorizontalWheelBridgeView()
    }

    func updateNSView(_ nsView: HorizontalWheelBridgeView, context: Context) {
        nsView.refreshScrollView()
    }
}

final class HorizontalWheelBridgeView: NSView {
    private weak var horizontalScrollView: NSScrollView?
    private var localMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshScrollView()
        updateLocalMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeLocalMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        refreshScrollView()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func refreshScrollView() {
        horizontalScrollView = sequence(first: superview, next: { $0?.superview })
            .compactMap { $0 as? NSScrollView }
            .first
    }

    private func updateLocalMonitor() {
        removeLocalMonitor()

        guard window != nil else {
            return
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.mappedScrollEvent(event)
        }
    }

    private func removeLocalMonitor() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func mappedScrollEvent(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window === window,
              let scrollView = horizontalScrollView,
              isMouseEvent(event, inside: scrollView) else {
            return event
        }

        let verticalMagnitude = abs(event.scrollingDeltaY)
        let horizontalMagnitude = abs(event.scrollingDeltaX)
        guard verticalMagnitude > horizontalMagnitude else {
            return event
        }

        let documentWidth = scrollView.documentView?.frame.width ?? 0
        let visibleWidth = scrollView.contentView.bounds.width
        guard documentWidth > visibleWidth else {
            return event
        }

        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let currentX = scrollView.contentView.bounds.origin.x
        let proposedX = currentX - (event.scrollingDeltaY * multiplier)
        let maxX = max(0, documentWidth - visibleWidth)
        let clampedX = min(max(proposedX, 0), maxX)
        guard clampedX != currentX else {
            return event
        }

        let newOrigin = NSPoint(x: clampedX, y: scrollView.contentView.bounds.origin.y)
        scrollView.contentView.scroll(to: newOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return nil
    }

    private func isMouseEvent(_ event: NSEvent, inside scrollView: NSScrollView) -> Bool {
        let pointInScrollView = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(pointInScrollView)
    }
}
