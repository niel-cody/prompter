import AppKit
import PrompterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var promptController: PromptController!
    private var statusItem: StatusItemController!
    private var hotKeys: HotKeyCenter!
    private var library: LibraryModel!
    private var libraryWindow: LibraryWindowController!
    private var meetings: MeetingController!
    private var meetingsWindow: MeetingsWindowController!
    private var settingsWindow: SettingsWindowController!
    private let updates = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        // One Prompter at a time. Two copies means two menu-bar icons and two claims on the
        // same global shortcuts, which is worse than useless. Debug modes are exempt so they
        // can run while the app is open.
        let isDebugRun = args.contains { $0.hasPrefix("--snapshot") || $0 == "--follow-test" || $0 == "--meeting-test" || $0 == "--diagnose" || $0.hasPrefix("--update-") }
        if !isDebugRun, let other = Self.otherRunningInstance() {
            other.activate()
            NSApp.terminate(nil)
            return
        }

        promptController = PromptController()
        library = LibraryModel(store: ScriptLibrary(directory: ScriptLibrary.defaultDirectory()))
        promptController.library = library
        libraryWindow = LibraryWindowController(library: library, prompt: promptController)
        let notesFolder = Preferences.shared.meetingNotesDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        meetings = MeetingController(store: MeetingStore(directory: MeetingStore.defaultDirectory(), markdownDirectory: notesFolder))
        meetings.library = library
        meetingsWindow = MeetingsWindowController(meetings: meetings)
        settingsWindow = SettingsWindowController(prompt: promptController, meetings: meetings)
        promptController.openSettings = { [weak self] in self?.settingsWindow.show() }
        statusItem = StatusItemController(prompt: promptController, meetings: meetings, updates: updates)
        statusItem.openLibrary = { [weak self] in self?.libraryWindow.show() }
        statusItem.openMeetings = { [weak self] in self?.meetingsWindow.show() }
        statusItem.newMeeting = { [weak self] template in self?.meetingsWindow.showNew(template: template) }
        statusItem.openSettings = { [weak self] in self?.settingsWindow.show() }
        updates.isBusy = { [weak self] in
            guard let self else { return false }
            return promptController.session.isRunning || meetings.isCapturing
        }
        if !isDebugRun {
            updates.startAutomaticChecks()
        }
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
        hotKeys.register(.markInsight) { [weak self] in self?.meetings.markInsight() }

        if args.contains("--diagnose") {
            Diagnostics.run(prompt: promptController, hotKeys: hotKeys)
        } else if let i = args.firstIndex(of: "--follow-test"), i + 1 < args.count {
            DebugSnapshot.runFollowTest(prompt: promptController, audioPath: args[i + 1])
        } else if let i = args.firstIndex(of: "--meeting-test"), i + 1 < args.count {
            let system = i + 2 < args.count && !args[i + 2].hasPrefix("--") ? args[i + 2] : nil
            DebugSnapshot.runMeetingTest(audioPath: args[i + 1], systemAudioPath: system)
        } else if let i = args.firstIndex(of: "--update-test"), i + 1 < args.count {
            let target = i + 2 < args.count && !args[i + 2].hasPrefix("--") ? args[i + 2] : nil
            UpdateTest.run(zipPath: args[i + 1], targetPath: target)
        } else if args.contains("--update-live") {
            UpdateTest.runLive(checker: updates)
        } else if let i = args.firstIndex(of: "--snapshot-update"), i + 1 < args.count {
            UpdateTest.snapshot(checker: updates, outputPath: args[i + 1])
        } else if let i = args.firstIndex(of: "--snapshot-window"), i + 2 < args.count {
            DebugSnapshot.runWindow(args[i + 1], library: libraryWindow, settings: settingsWindow, meetings: meetingsWindow,
                                    model: library, meetingModel: meetings, outputPath: args[i + 2])
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

    /// Another copy of Prompter already running, launched from a different location.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        libraryWindow.show()
        return true
    }
}
