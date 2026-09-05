import AppKit
import SwiftUI
import PrompterCore

/// Presents the delivery review in a regular window once a session finishes. This is the
/// one moment Prompter is allowed to take focus: the presentation is over.
@MainActor
final class ReviewWindowController {
    private var window: NSWindow?

    func show(review: DeliveryReview, title: String, onPresentAgain: @escaping () -> Void) {
        let view = ReviewView(review: review, title: title,
                              onPresentAgain: { [weak self] in self?.close(); onPresentAgain() },
                              onClose: { [weak self] in self?.close() })
        let host = NSHostingController(rootView: view)
        let window = self.window ?? makeWindow()
        window.contentViewController = host
        window.title = "Delivery Review"
        // Size the window to the card's natural height; the notes vary in length.
        let fitting = host.sizeThatFits(in: NSSize(width: 440, height: 2000))
        window.setContentSize(NSSize(width: 440, height: ceil(fitting.height)))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
