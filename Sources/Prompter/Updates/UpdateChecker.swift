import AppKit
import Foundation
import Observation
import PrompterCore

/// Looks at the latest GitHub release and tells the user when there's a newer Prompter.
/// Deliberately small: one unauthenticated GET, no downloads in the background, no
/// identifying data sent. Swap for Sparkle when the audience outgrows it.
@MainActor
@Observable
final class UpdateChecker {
    typealias Release = ReleaseInfo

    static let releasesAPI = URL(string: "https://api.github.com/repos/niel-cody/prompter/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// A newer release we know about, for the menu to surface.
    private(set) var available: Release?
    private(set) var isChecking = false

    let currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private let preferences = Preferences.shared
    private var timer: Timer?

    /// Starts the quiet daily check if the user has it on.
    func startAutomaticChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.automaticCheckIfDue() }
        }
        Task { await automaticCheckIfDue() }
    }

    private func automaticCheckIfDue() async {
        guard preferences.checkForUpdatesAutomatically else { return }
        let last = preferences.lastUpdateCheck ?? .distantPast
        guard Date().timeIntervalSince(last) >= Self.checkInterval else { return }
        if let release = await fetchLatest(), ReleaseFeed.isNewer(release.version, than: currentVersion),
           release.version != preferences.skippedUpdateVersion {
            available = release
        }
    }

    /// Explicit "Check for Updates…" from the menu: always reports a result.
    func checkNow() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        guard let release = await fetchLatest() else {
            alert(title: "Couldn't check for updates",
                  message: "Prompter couldn't reach GitHub. Check your connection and try again.")
            return
        }
        if ReleaseFeed.isNewer(release.version, than: currentVersion) {
            available = release
            offer(release)
        } else {
            available = nil
            alert(title: "You're up to date", message: "Prompter \(currentVersion) is the latest version.")
        }
    }

    func offerAvailable() {
        if let available { offer(available) }
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "Prompter \(release.version) is available"
        alert.informativeText = "You have \(currentVersion).\n\n" + release.notes.prefix(1200)
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.downloadURL ?? release.pageURL)
        case .alertThirdButtonReturn:
            preferences.skippedUpdateVersion = release.version
            available = nil
        default:
            break
        }
    }

    private func alert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    // MARK: - GitHub

    private func fetchLatest() async -> Release? {
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Prompter/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            preferences.lastUpdateCheck = Date()
            return ReleaseFeed.parseLatest(data)
        } catch {
            return nil
        }
    }

}
