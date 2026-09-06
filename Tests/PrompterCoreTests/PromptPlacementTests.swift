import CoreGraphics
import Testing
import Foundation
@testable import PrompterCore

@Suite struct PromptPlacementTests {
    /// MacBook Pro 14" at its default scaled resolution: 1512×982 points, 32pt notch row,
    /// notch about 175pt wide, centred.
    static let macBookPro = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        safeAreaTop: 32,
        auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 668, height: 32),
        auxiliaryTopRight: CGRect(x: 843, y: 950, width: 669, height: 32)
    )

    /// The external 1080p monitor on the desk here: no notch, menu bar 30pt.
    static let externalDisplay = DisplayGeometry(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1050)
    )

    /// A second display placed to the right of the built-in one.
    static let secondaryToTheRight = DisplayGeometry(
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1050)
    )

    let panel = CGSize(width: 560, height: 208)

    @Test func notchIsDetectedAndCameraSitsAboveTheGap() {
        let p = PromptPlacement(display: Self.macBookPro)
        #expect(p.hasNotch)
        // Camera is centred in the notch, which is centred on the display.
        #expect(abs(p.cameraCenterX - 755.5) < 1)
        #expect(abs(p.cameraCenterX - Self.macBookPro.frame.midX) < 2)
        // The prompt starts below the notch row, not inside it.
        #expect(p.topEdgeY == 950)
    }

    @Test func promptHugsTheCameraOnANotchedMac() {
        let display = Self.macBookPro
        let p = PromptPlacement(display: display)
        let frame = p.frame(size: panel, in: display)
        #expect(abs(frame.midX - p.cameraCenterX) < 0.5)
        #expect(frame.maxY == 944)                    // 6pt below the notch
        #expect(display.frame.maxY - frame.maxY == 38) // notch row + gap: eyes stay high
        #expect(frame.size == panel)
    }

    @Test func externalDisplayFallsBackToTopCentre() {
        let display = Self.externalDisplay
        let p = PromptPlacement(display: display)
        #expect(!p.hasNotch)
        #expect(p.cameraCenterX == 960)
        #expect(p.topEdgeY == 1050)
        let frame = p.frame(size: panel, in: display)
        #expect(frame.origin == CGPoint(x: 680, y: 836))
    }

    @Test func placementRespectsADisplayThatIsNotAtTheOrigin() {
        let display = Self.secondaryToTheRight
        let frame = PromptPlacement(display: display).frame(size: panel, in: display)
        #expect(frame.midX == display.frame.midX)
        #expect(display.visibleFrame.contains(frame))
    }

    @Test func aPanelWiderThanTheScreenIsClampedOnScreen() {
        let display = DisplayGeometry(frame: CGRect(x: 0, y: 0, width: 400, height: 600),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 400, height: 570))
        let frame = PromptPlacement(display: display).frame(size: panel, in: display)
        #expect(frame.width == 400)
        #expect(display.visibleFrame.contains(frame))
    }

    @Test func autoHiddenMenuBarStillPlacesBelowTheNotch() {
        // Menu bar hidden: the inset can come back as zero even though the notch is there.
        var display = Self.macBookPro
        display.safeAreaTop = 0
        display.visibleFrame = display.frame
        let p = PromptPlacement(display: display)
        #expect(p.hasNotch)
        #expect(p.topEdgeY == display.frame.maxY)
    }

    @Test func remeberedFramesAreRejectedWhenTheyNoLongerFit() {
        let min = CGSize(width: 320, height: 110)
        let onScreen = CGRect(x: 680, y: 836, width: 560, height: 208)
        #expect(PromptPlacement.isUsable(onScreen, on: Self.externalDisplay, minSize: min))
        // Saved on a wider display that has since been unplugged.
        let offToTheRight = CGRect(x: 2600, y: 836, width: 560, height: 208)
        #expect(!PromptPlacement.isUsable(offToTheRight, on: Self.externalDisplay, minSize: min))
        // Mostly off the bottom.
        let halfOff = CGRect(x: 680, y: -150, width: 560, height: 208)
        #expect(!PromptPlacement.isUsable(halfOff, on: Self.externalDisplay, minSize: min))
        // Too small to read.
        let tiny = CGRect(x: 680, y: 836, width: 100, height: 40)
        #expect(!PromptPlacement.isUsable(tiny, on: Self.externalDisplay, minSize: min))
    }
}
