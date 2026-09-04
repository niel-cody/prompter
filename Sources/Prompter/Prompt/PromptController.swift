import AppKit
import SwiftUI
import PrompterCore

/// Owns the prompt panel and the current session. Everything that "shows a prompt" goes
/// through here: clipboard, menu, shortcuts, the editor.
@MainActor
final class PromptController {
    let session: PromptSession
    private(set) var appearance = PromptAppearance()
    private var panel: PromptPanel?
    private let parser = PhraseParser()

    static let defaultSize = CGSize(width: 560, height: 190)

    init() {
        session = PromptSession(script: PresentationScript(sourceText: "", sections: [], phrases: []), title: "")
    }

    var isVisible: Bool { panel?.isVisible ?? false }
    /// For the `--snapshot` debug mode only.
    var debugPanel: PromptPanel? { panel }

    // MARK: - Presenting

    func present(text: String, title: String) {
        let script = parser.parse(text)
        session.load(script: script, title: title)
        show()
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
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Clipboard"
        present(text: text, title: String(firstLine.prefix(60)))
    }

    func show() {
        let panel = panel ?? makePanel()
        if !panel.isVisible {
            panel.setFrame(placementFrame(), display: false)
        }
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    func toggleVisibility() { isVisible ? hide() : show() }

    /// Snap back under the camera on the display the user is looking at.
    func recenterUnderCamera() {
        panel?.setFrame(placementFrame(), display: true, animate: true)
    }

    // MARK: - Panel

    private func makePanel() -> PromptPanel {
        let panel = PromptPanel(contentRect: placementFrame())
        let host = NSHostingView(rootView: PromptView(session: session, appearance: appearance))
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func placementFrame() -> NSRect {
        let size = panel?.frame.size ?? Self.defaultSize
        return CameraPlacement(screen: CameraPlacement.preferredScreen()).defaultFrame(size: size)
    }
}
