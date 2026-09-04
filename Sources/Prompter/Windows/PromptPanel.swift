import AppKit
import SwiftUI

/// The floating window that shows the prompt. It stays above everything, joins every
/// Space (including full-screen Zoom/Keynote), and never activates Prompter when clicked,
/// so the meeting app keeps focus.
final class PromptPanel: NSPanel {
    /// Called for key presses while the panel is key (after the user clicks it).
    var onKeyDown: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = NSSize(width: 320, height: 110)
    }

    // Borderless windows refuse key status by default. Allowing it lets local shortcuts
    // (arrows, space) work after a click, still without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }
}
