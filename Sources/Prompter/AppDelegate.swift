import AppKit
import PrompterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var promptController: PromptController!
    private var statusItem: StatusItemController!
    private var hotKeys: HotKeyCenter!

    func applicationDidFinishLaunching(_ notification: Notification) {
        promptController = PromptController()
        statusItem = StatusItemController(prompt: promptController)
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
        if let i = args.firstIndex(of: "--snapshot-review"), i + 1 < args.count {
            DebugSnapshot.runReview(outputPath: args[i + 1])
        } else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            DebugSnapshot.run(prompt: promptController, hotKeys: hotKeys, outputPath: args[i + 1])
        } else if args.contains("--sample") {
            promptController.present(text: SampleScript.text, title: "Sample")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
