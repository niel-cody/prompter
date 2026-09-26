import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let prompt: PromptController
    private let meetings: MeetingController

    init(prompt: PromptController, meetings: MeetingController) {
        self.prompt = prompt
        self.meetings = meetings
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(prompt: prompt, meetings: meetings, preferences: Preferences.shared))
        let window = NSWindow(contentViewController: host)
        window.title = "Prompter Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
