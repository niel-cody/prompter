import AppKit
import SwiftUI
import PrompterCore

/// Owns the prompt panel and the current session. Everything that "shows a prompt" goes
/// through here: clipboard, menu, shortcuts, the editor.
@MainActor
final class PromptController {
    let session: PromptSession
    let voice = VoiceFollowController()
    let reviewWindow = ReviewWindowController()
    let preferences = Preferences.shared
    private var panel: PromptPanel?
    private let parser = PhraseParser()
    private var observers: [NSObjectProtocol] = []
    /// Called when the user asks for Settings from the prompt's hover controls.
    var openSettings: (() -> Void)?
    /// Saves clipboard prompts so they show up under Recent Prompts.
    var library: LibraryModel?
    private(set) var currentDocumentID: UUID?

    static let defaultSize = CGSize(width: 560, height: 208)

    init() {
        session = PromptSession(script: PresentationScript(sourceText: "", sections: [], phrases: []), title: "",
                                style: Preferences.shared.style)
        session.mode = preferences.mode
        voice.setEnabled(preferences.voiceFollowEnabled)
        voice.attach(to: session)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.screensChanged() }
        })
        session.onJump = { [weak self] phrase, source in
            if source == .user { self?.voice.reanchor(toPhrase: phrase) }
        }
        session.onRunningChanged = { [weak self] running in
            guard let self else { return }
            if running, session.mode == .coach { voice.startListening() } else { voice.stopListening() }
        }
        session.onFinished = { [weak self] in self?.showReview() }
    }

    /// End the session now and show how it went.
    func endSession() {
        guard session.log.startedAt != nil else { return }
        session.finish()
    }

    private func showReview() {
        let review = DeliveryReview(log: session.log, script: session.script, plan: session.plan,
                                    styleName: session.style.displayName)
        hide()
        reviewWindow.show(review: review, title: session.title) { [weak self] in
            guard let self else { return }
            session.reset()
            voice.rebuildMatcher()
            show()
        }
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// For the `--snapshot` debug mode only.
    var debugPanel: PromptPanel? { panel }

    // MARK: - Presenting

    func present(text: String, title: String, documentID: UUID? = nil) {
        let script = parser.parse(text)
        session.load(script: script, title: title)
        voice.rebuildMatcher()
        currentDocumentID = documentID
        show()
    }

    func present(_ document: ScriptDocument) {
        library?.markPresented(document.id)
        present(text: document.text, title: document.title, documentID: document.id)
    }

    /// Clipboard Prompt: whatever is on the pasteboard becomes the prompt, instantly.
    func promptClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            NSSound.beep()
            return
        }
        let title = ScriptDocument.inferredTitle(from: text)
        // Save it quietly so it appears under Recent Prompts and can be edited later.
        let saved = library?.saveClipboardPrompt(title: title, text: text)
        present(text: text, title: title, documentID: saved?.id)
    }

    func show() {
        let panel = panel ?? makePanel()
        if !panel.isVisible {
            panel.setFrame(restoredOrDefaultFrame(), display: false)
        }
        panel.orderFrontRegardless()
    }

    func setStyle(_ style: DeliveryStyle) {
        session.setStyle(style)
        preferences.style = style
    }

    func setMode(_ mode: ReadingMode) {
        session.mode = mode
        preferences.mode = mode
        if mode != .coach { voice.stopListening() } else if session.isRunning { voice.startListening() }
    }

    func setVoiceFollow(_ enabled: Bool) {
        voice.setEnabled(enabled)
        preferences.voiceFollowEnabled = enabled
    }

    func hide() { panel?.orderOut(nil) }

    func toggleVisibility() { isVisible ? hide() : show() }

    /// Snap back under the camera on the display the user is looking at.
    func recenterUnderCamera() {
        panel?.setFrame(placementFrame(), display: true, animate: true)
        rememberFrame()
    }

    // MARK: - Panel

    private func makePanel() -> PromptPanel {
        let panel = PromptPanel(contentRect: placementFrame())
        let actions = PromptActions(
            hide: { [weak self] in self?.hide() },
            endSession: { [weak self] in self?.endSession() },
            openSettings: { [weak self] in self?.openSettings?() },
            setStyle: { [weak self] in self?.setStyle($0) },
            snapToCamera: { [weak self] in self?.recenterUnderCamera() }
        )
        let host = NSHostingView(rootView: PromptView(session: session, voice: voice, preferences: preferences, actions: actions))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.acceptsMouseMovedEvents = true
        panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.rememberFrame() }
            })
        }
        self.panel = panel
        return panel
    }

    /// The user's last position on this display, if it still fits; otherwise under the camera.
    private func restoredOrDefaultFrame() -> NSRect {
        let screen = CameraPlacement.preferredScreen()
        if let saved = preferences.panelFrame(for: screen), screen.visibleFrame.intersects(saved),
           saved.width >= 320, saved.height >= 110 {
            return saved
        }
        return placementFrame()
    }

    private func rememberFrame() {
        guard let panel, panel.isVisible, let screen = panel.screen else { return }
        preferences.setPanelFrame(panel.frame, for: screen)
    }

    /// A display was added or removed. If ours went away, come back on the best remaining one.
    private func screensChanged() {
        guard let panel, panel.isVisible else { return }
        if panel.screen == nil || !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) {
            panel.setFrame(restoredOrDefaultFrame(), display: true)
        }
    }

    // MARK: - Keyboard (panel is key after a click; global shortcuts cover the rest)

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let key = event.charactersIgnoringModifiers?.first else { return false }
        let option = event.modifierFlags.contains(.option)
        switch key {
        case " ":
            session.toggleRunning()
        case Character(UnicodeScalar(NSRightArrowFunctionKey)!), Character(UnicodeScalar(NSDownArrowFunctionKey)!):
            option ? session.nextSection() : session.advance()
        case Character(UnicodeScalar(NSLeftArrowFunctionKey)!), Character(UnicodeScalar(NSUpArrowFunctionKey)!):
            option ? session.previousSection() : session.retreat()
        case "\u{1B}":
            hide()
        case "r" where event.modifierFlags.contains(.command):
            session.reset()
        case "=", "+":
            preferences.adjustFontSize(by: 2)
        case "-":
            preferences.adjustFontSize(by: -2)
        default:
            return false
        }
        return true
    }

    private func placementFrame() -> NSRect {
        let size = panel?.frame.size ?? Self.defaultSize
        return CameraPlacement(screen: CameraPlacement.preferredScreen()).defaultFrame(size: size)
    }
}
