import AppKit
import Foundation
import Observation
import PrompterCore

/// Everything the user has chosen, persisted as one small JSON blob in UserDefaults.
/// Observable so the prompt re-renders the moment a setting changes.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private struct Stored: Codable {
        var appearance = PromptAppearance()
        var style = DeliveryStyle.professional
        var mode = ReadingMode.coach
        var voiceFollowEnabled = true
        var panelFrames: [String: CGRect] = [:]
        var hasCompletedOnboarding = false
        var classicScrollSpeed: Double = 1.0
        var checkForUpdatesAutomatically = true
        var lastUpdateCheck: Date? = nil
        var skippedUpdateVersion: String? = nil
    }

    private static let key = "Prompter.preferences"
    private var stored: Stored { didSet { persist() } }
    private var suppressPersist = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            stored = Stored()
        }
        // Debug snapshot runs must never write back into the user's real preferences.
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--snapshot") }) {
            suppressPersist = true
            if ProcessInfo.processInfo.environment["PROMPTER_SNAPSHOT_THEME"] == "light" { stored.appearance.theme = .light }
        }
    }

    var appearance: PromptAppearance {
        get { stored.appearance }
        set { stored.appearance = newValue }
    }
    var style: DeliveryStyle {
        get { stored.style }
        set { stored.style = newValue }
    }
    var mode: ReadingMode {
        get { stored.mode }
        set { stored.mode = newValue }
    }
    var voiceFollowEnabled: Bool {
        get { stored.voiceFollowEnabled }
        set { stored.voiceFollowEnabled = newValue }
    }
    var hasCompletedOnboarding: Bool {
        get { stored.hasCompletedOnboarding }
        set { stored.hasCompletedOnboarding = newValue }
    }
    var checkForUpdatesAutomatically: Bool {
        get { stored.checkForUpdatesAutomatically }
        set { stored.checkForUpdatesAutomatically = newValue }
    }
    var lastUpdateCheck: Date? {
        get { stored.lastUpdateCheck }
        set { stored.lastUpdateCheck = newValue }
    }
    var skippedUpdateVersion: String? {
        get { stored.skippedUpdateVersion }
        set { stored.skippedUpdateVersion = newValue }
    }
    var classicScrollSpeed: Double {
        get { stored.classicScrollSpeed }
        set { stored.classicScrollSpeed = min(2.0, max(0.5, newValue)) }
    }

    // MARK: - Panel position per display

    func panelFrame(for screen: NSScreen) -> CGRect? {
        stored.panelFrames[Self.key(for: screen)]
    }

    func setPanelFrame(_ frame: CGRect, for screen: NSScreen) {
        stored.panelFrames[Self.key(for: screen)] = frame
    }

    /// A stable identity for a display across reconnects: its CoreGraphics UUID.
    static func key(for screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    // MARK: - Font / opacity nudges

    func adjustFontSize(by delta: CGFloat) {
        appearance.fontSize = min(56, max(18, appearance.fontSize + delta))
    }

    func adjustOpacity(by delta: Double) {
        appearance.backgroundOpacity = min(1.0, max(0.2, appearance.backgroundOpacity + delta))
    }

    private func persist() {
        guard !suppressPersist, let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
