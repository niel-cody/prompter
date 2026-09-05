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
        // Size the window to the card's natural height; the notes vary in length. Text wrapping
        // settles only after a layout pass, so measure once now and once more after it.
        fit(window, to: host)
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window === window else { return }
            self.fit(window, to: host)
        }
    }

    private func fit(_ window: NSWindow, to host: NSHostingController<ReviewView>) {
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.sizeThatFits(in: NSSize(width: 440, height: 2000))
        let target = NSSize(width: 440, height: ceil(fitting.height))
        guard abs(window.contentLayoutRect.height - target.height) > 0.5 else { return }
        let oldFrame = window.frame
        window.setContentSize(target)
        // Keep the top edge where it was so the card grows downwards, not off the top.
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
