import AppKit
import SwiftUI
import PrompterCore

/// Owns the one window and the first-run sheet on it.
@MainActor
final class MainWindowController {
    let workspace: Workspace
    private var window: NSWindow?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    func show(_ area: Workspace.Area? = nil) {
        if let area { workspace.focus(area) }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func showNewScript() {
        workspace.newScript()
        show()
    }

    func showNewMeeting(template: MeetingTemplate) {
        workspace.newMeeting(template)
        show()
    }

    /// First run: the welcome card as a sheet on the window, not a window of its own.
    func showOnboarding() {
        show()
        guard let window else { return }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(
            onTrySample: { [weak self, weak window] in
                guard let self, let window else { return }
                Preferences.shared.hasCompletedOnboarding = true
                window.endSheet(window.attachedSheet ?? window)
                let doc = workspace.library.saveClipboardPrompt(title: "Sample: inventory update", text: SampleScript.text)
                if let doc { workspace.prompt.present(doc) } else { workspace.prompt.present(text: SampleScript.text, title: "Sample") }
                workspace.prompt.session.start()
            },
            onSkip: { [weak window] in
                Preferences.shared.hasCompletedOnboarding = true
                if let window, let sheet = window.attachedSheet { window.endSheet(sheet) }
            }
        )))
        sheet.title = "Welcome to Prompter"
        sheet.styleMask = [.titled, .fullSizeContentView]
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        window.beginSheet(sheet)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: MainView(workspace: workspace))
        let window = NSWindow(contentViewController: host)
        window.title = "Prompter"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1040, height: 640))
        window.center()
        window.setFrameAutosaveName("Prompter.Main")
        return window
    }
}
