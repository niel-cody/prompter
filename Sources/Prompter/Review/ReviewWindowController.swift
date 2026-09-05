import AppKit
import SwiftUI
import PrompterCore

/// Presents the delivery review in a regular window once a session finishes. This is the
/// one moment Prompter is allowed to take focus: the presentation is over.
@MainActor
final class ReviewWindowController {
    private var window: NSWindow?

    func show(review: DeliveryReview, title: String, onPresentAgain: @escaping () -> Void) {
        let window = self.window ?? makeWindow()
        let view = ReviewView(review: review, title: title,
                              onPresentAgain: { [weak self] in self?.close(); onPresentAgain() },
                              onClose: { [weak self] in self?.close() },
                              onHeightChange: { [weak window] height in
                                  guard let window else { return }
                                  Self.fit(window, toHeight: height)
                              })
        let host = NSHostingController(rootView: view)
        // The view reports its own laid-out height; don't let the hosting view fight it.
        host.sizingOptions = []
        window.contentViewController = host
        window.title = "Delivery Review"
        window.setContentSize(NSSize(width: 440, height: 420))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Grow or shrink the window to the card's natural height, keeping its top edge put.
    private static func fit(_ window: NSWindow, toHeight height: CGFloat) {
        let target = ceil(height)
        guard target > 0, abs(window.contentLayoutRect.height - target) > 0.5 else { return }
        let oldFrame = window.frame
        window.setContentSize(NSSize(width: 440, height: target))
        window.setFrameTopLeftPoint(NSPoint(x: oldFrame.minX, y: oldFrame.maxY))
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        return window
    }
}
