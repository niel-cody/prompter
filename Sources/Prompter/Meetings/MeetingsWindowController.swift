import AppKit
import SwiftUI
import PrompterCore

@MainActor
final class MeetingsWindowController {
    private var window: NSWindow?
    private let meetings: MeetingController

    init(meetings: MeetingController) {
        self.meetings = meetings
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Open the window on a fresh note from `template`.
    func showNew(template: MeetingTemplate) {
        meetings.create(template: template)
        show()
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: MeetingsView(meetings: meetings))
        let window = NSWindow(contentViewController: host)
        window.title = "Meetings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1040, height: 640))
        window.center()
        window.setFrameAutosaveName("Prompter.Meetings")
        return window
    }
}
