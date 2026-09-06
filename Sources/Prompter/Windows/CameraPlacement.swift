import AppKit
import PrompterCore

/// Bridges `NSScreen` to the testable placement maths in PrompterCore.
enum CameraPlacement {
    static func geometry(of screen: NSScreen) -> DisplayGeometry {
        DisplayGeometry(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
    }

    static func placement(for screen: NSScreen) -> PromptPlacement {
        PromptPlacement(display: geometry(of: screen))
    }

    static func defaultFrame(size: CGSize, on screen: NSScreen) -> NSRect {
        let geo = geometry(of: screen)
        return PromptPlacement(display: geo).frame(size: size, in: geo)
    }

    /// The display the user is most likely presenting on: the one with the mouse, since that
    /// is where their attention (and usually their meeting window) is.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Prefer a display with a notch: that is where the camera is. Otherwise the built-in
    /// display, otherwise wherever the mouse is.
    static func preferredScreen() -> NSScreen {
        if let notched = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) { return notched }
        return activeScreen()
    }
}
