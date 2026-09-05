import AppKit
import PrompterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var promptController: PromptController!
    private var statusItem: StatusItemController!
    private var hotKeys: HotKeyCenter!
    private var library: LibraryModel!
    private var libraryWindow: LibraryWindowController!
    private var settingsWindow: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        promptController = PromptController()
        library = LibraryModel(store: ScriptLibrary(directory: ScriptLibrary.defaultDirectory()))
        promptController.library = library
        libraryWindow = LibraryWindowController(library: library, prompt: promptController)
        settingsWindow = SettingsWindowController(prompt: promptController)
        promptController.openSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem = StatusItemController(prompt: promptController)
        statusItem.openLibrary = { [weak self] in self?.libraryWindow.show() }
        statusItem.openSettings = { [weak self] in self?.settingsWindow.show() }
        hotKeys = HotKeyCenter()
        hotKeys.register(.promptClipboard) { [weak self] in self?.promptController.promptClipboard() }
        hotKeys.register(.toggleVisibility) { [weak self] in self?.promptController.toggleVisibility() }
        hotKeys.register(.startPause) { [weak self] in self?.promptController.session.toggleRunning() }
        hotKeys.register(.nextPhrase) { [weak self] in self?.promptController.session.advance() }
        hotKeys.register(.previousPhrase) { [weak self] in self?.promptController.session.retreat() }
        hotKeys.register(.nextSection) { [weak self] in self?.promptController.session.nextSection() }
        hotKeys.register(.previousSection) { [weak self] in self?.promptController.session.previousSection() }
        hotKeys.register(.endSession) { [weak self] in self?.promptController.endSession() }
        hotKeys.register(.fontLarger) { Preferences.shared.adjustFontSize(by: 2) }
        hotKeys.register(.fontSmaller) { Preferences.shared.adjustFontSize(by: -2) }

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--follow-test"), i + 1 < args.count {
            DebugSnapshot.runFollowTest(prompt: promptController, audioPath: args[i + 1])
        } else if let i = args.firstIndex(of: "--snapshot-window"), i + 2 < args.count {
            DebugSnapshot.runWindow(args[i + 1], library: libraryWindow, settings: settingsWindow, model: library, outputPath: args[i + 2])
        } else if let i = args.firstIndex(of: "--snapshot-review"), i + 1 < args.count {
            DebugSnapshot.runReview(prompt: promptController, outputPath: args[i + 1])
        } else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            DebugSnapshot.run(prompt: promptController, hotKeys: hotKeys, outputPath: args[i + 1])
        } else if args.contains("--sample") {
            promptController.present(text: SampleScript.text, title: "Sample")
        } else if !Preferences.shared.hasCompletedOnboarding {
            libraryWindow.showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        libraryWindow.show()
        return true
    }
}
