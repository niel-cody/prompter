import CoreGraphics
import Foundation

/// The geometry of one display, in screen coordinates, as far as prompt placement cares.
/// Kept free of AppKit so the notch maths can be tested without the hardware.
public struct DisplayGeometry: Sendable, Equatable {
    /// The whole display, including the menu bar and any notch row.
    public var frame: CGRect
    /// What's left after the menu bar and Dock.
    public var visibleFrame: CGRect
    /// Height of the notch / menu-bar safe area. Zero on displays without a notch.
    public var safeAreaTop: CGFloat
    /// The usable strip to the left of the notch, when there is one.
    public var auxiliaryTopLeft: CGRect?
    /// The usable strip to the right of the notch.
    public var auxiliaryTopRight: CGRect?

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat = 0,
                auxiliaryTopLeft: CGRect? = nil, auxiliaryTopRight: CGRect? = nil) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }
}

/// Where the camera is on a display, and where the prompt should sit to hug it.
///
/// On a MacBook the camera lives in the notch, so the prompt goes directly beneath it.
/// On any other display we assume the common case: a webcam on the top bezel, horizontally
/// centred, so the prompt sits top-centre just under the menu bar.
public struct PromptPlacement: Sendable, Equatable {
    /// x coordinate of the camera's centre, in screen coordinates.
    public let cameraCenterX: CGFloat
    /// y coordinate of the first row of pixels usable beneath the camera / menu bar.
    public let topEdgeY: CGFloat
    public let hasNotch: Bool

    public init(display: DisplayGeometry) {
        if let left = display.auxiliaryTopLeft, let right = display.auxiliaryTopRight, right.minX > left.maxX {
            // The notch spans the gap between the two auxiliary areas, and the camera is
            // centred in it.
            cameraCenterX = (left.maxX + right.minX) / 2
            hasNotch = true
            // Sit below the notch row. safeAreaTop covers it; visibleFrame is the fallback
            // if the menu bar is auto-hidden and the inset comes back as zero.
            let belowNotch = display.frame.maxY - display.safeAreaTop
            topEdgeY = display.safeAreaTop > 0 ? belowNotch : min(display.visibleFrame.maxY, display.frame.maxY)
        } else {
            cameraCenterX = display.frame.midX
            hasNotch = false
            topEdgeY = display.visibleFrame.maxY
        }
    }

    /// A panel frame of `size` centred under the camera, `gap` points below it, kept on screen.
    public func frame(size: CGSize, in display: DisplayGeometry, gap: CGFloat = 6) -> CGRect {
        let visible = display.visibleFrame
        // Never propose a panel wider or taller than the display can show.
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        var origin = CGPoint(x: cameraCenterX - width / 2, y: topEdgeY - gap - height)
        origin.x = max(visible.minX, min(origin.x, visible.maxX - width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - height))
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    /// Is a remembered frame still usable on this display? Guards against a panel restored
    /// from a display that has since changed resolution or been unplugged.
    public static func isUsable(_ frame: CGRect, on display: DisplayGeometry, minSize: CGSize) -> Bool {
        guard frame.width >= minSize.width, frame.height >= minSize.height else { return false }
        let visible = display.visibleFrame
        guard visible.intersects(frame) else { return false }
        // At least most of the panel, and its top edge, must be on screen.
        let overlap = visible.intersection(frame)
        let covered = (overlap.width * overlap.height) / (frame.width * frame.height)
        return covered >= 0.9 && frame.maxY <= visible.maxY + 1
    }
}
