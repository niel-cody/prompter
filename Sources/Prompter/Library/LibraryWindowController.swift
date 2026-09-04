import AppKit
import SwiftUI
import PrompterCore

@MainActor
final class LibraryWindowController {
    private var window: NSWindow?
    private var onboardingWindow: NSWindow?
    private let library: LibraryModel
    private let prompt: PromptController

    init(library: LibraryModel, prompt: PromptController) {
        self.library = library
        self.prompt = prompt
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func showOnboarding() {
        let view = OnboardingView(
            onTrySample: { [weak self] in
                guard let self else { return }
                Preferences.shared.hasCompletedOnboarding = true
                onboardingWindow?.orderOut(nil)
                let doc = library.saveClipboardPrompt(title: "Sample: inventory update", text: SampleScript.text)
                if let doc { prompt.present(doc) } else { prompt.present(text: SampleScript.text, title: "Sample") }
                prompt.session.start()
            },
            onSkip: { [weak self] in
                Preferences.shared.hasCompletedOnboarding = true
                self?.onboardingWindow?.orderOut(nil)
                self?.show()
            }
        )
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to Prompter"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: LibraryView(library: library, prompt: prompt))
        let window = NSWindow(contentViewController: host)
        window.title = "Prompter"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        window.setFrameAutosaveName("Prompter.Library")
        return window
    }
}
