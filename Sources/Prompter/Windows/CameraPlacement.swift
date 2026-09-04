import AppKit

/// Works out where the camera is on a display and where the prompt should sit to hug it.
///
/// On a MacBook with a notch, the camera is in the notch and the panel goes right under it.
/// On any other display we assume the common case: a webcam clipped to the top bezel,
/// horizontally centred, so the prompt sits at the top centre just under the menu bar.
struct CameraPlacement {
    let screen: NSScreen
    /// x coordinate (screen space) of the camera's centre.
    let cameraCenterX: CGFloat
    /// y coordinate (screen space) of the first usable pixel row under the camera / menu bar.
    let topEdgeY: CGFloat
    let hasNotch: Bool

    init(screen: NSScreen) {
        self.screen = screen
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            // The notch spans the gap between the two auxiliary areas.
            cameraCenterX = (left.maxX + right.minX) / 2
            topEdgeY = frame.maxY - screen.safeAreaInsets.top
            hasNotch = true
        } else {
            cameraCenterX = frame.midX
            topEdgeY = screen.visibleFrame.maxY
            hasNotch = false
        }
    }

    /// Default panel frame of `size`, centred under the camera with a small gap.
    func defaultFrame(size: CGSize, gap: CGFloat = 6) -> NSRect {
        var origin = NSPoint(x: cameraCenterX - size.width / 2, y: topEdgeY - gap - size.height)
        // Keep it on screen on very narrow displays.
        let visible = screen.visibleFrame
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, origin.y)
        return NSRect(origin: origin, size: size)
    }

    /// The display the user is most likely presenting on: the one with the mouse, since that
    /// is where their attention (and usually their meeting window) is.
    static func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// Prefer the built-in display when there is one: that is where the camera is.
    static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil } ?? activeScreen()
    }
}
