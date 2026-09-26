import AppKit
import SwiftUI

/// The single "Software Update" window. Its content is `UpdateView`, driven by the
/// checker's phase, so checking, what's new, progress and failure all live in one place.
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private unowned let checker: UpdateChecker

    init(checker: UpdateChecker) {
        self.checker = checker
    }

    /// `activating: false` brings the window forward without stealing focus, for an update
    /// found in the background.
    func show(activating: Bool) {
        let window = self.window ?? makeWindow()
        self.window = window
        if activating {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    func close() {
        window?.orderOut(nil)
    }

    var contentView: NSView? { window?.contentView }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: UpdateView(checker: checker))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Software Update"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        checker.windowDidClose()
    }
}
