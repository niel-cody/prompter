import AppKit
import Foundation
import Observation
import PrompterCore

/// Finds newer releases on GitHub and installs them in place, telling the user what is
/// happening at each step. One unauthenticated GET a day for the check, nothing about the
/// user sent. The window is `UpdateView`; the downloading and swapping is `UpdateInstaller`.
@MainActor
@Observable
final class UpdateChecker {
    typealias Release = ReleaseInfo

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(received: Int64, total: Int64?)
        case verifying
        case installing
        case restarting
        case failed(String)
    }

    static let releasesAPI = URL(string: "https://api.github.com/repos/niel-cody/prompter/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/niel-cody/prompter/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60

    private(set) var phase: Phase = .idle
    /// A newer release we know about, for the menu to surface.
    private(set) var available: Release?

    var isChecking: Bool { phase == .checking }
    var isInstalling: Bool {
        switch phase {
        case .downloading, .verifying, .installing, .restarting: true
        default: false
        }
    }

    /// Set by the app: true while a prompt or a meeting is live, so an update found in the
    /// background never pops up mid-pitch.
    @ObservationIgnored var isBusy: () -> Bool = { false }

    let currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    @ObservationIgnored private let preferences = Preferences.shared
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var window: UpdateWindowController!
    /// Off only for `--update-live`, which wants to inspect the result rather than reopen.
    @ObservationIgnored var relaunchesAfterInstall = true

    init() {
        window = UpdateWindowController(checker: self)
    }

    // MARK: - Checking

    /// Starts the quiet daily check if the user has it on.
    func startAutomaticChecks() {
        UpdateInstaller().sweepLeftovers()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.automaticTick() }
        }
        Task { await automaticTick() }
    }

    private func automaticTick() async {
        guard preferences.checkForUpdatesAutomatically, !isInstalling, !isChecking else { return }
        let last = preferences.lastUpdateCheck ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.checkInterval, let release = await fetchLatest() {
            let newer = ReleaseFeed.isNewer(release.version, than: currentVersion)
            available = newer && release.version != preferences.skippedUpdateVersion ? release : nil
        }
        offerQuietlyIfNew()
    }

    /// Shows the window once per version without taking focus, and never during a pitch or
    /// a meeting. The menu keeps offering it either way.
    private func offerQuietlyIfNew() {
        guard let release = available, phase == .idle || phase == .upToDate,
              preferences.lastOfferedUpdateVersion != release.version, !isBusy() else { return }
        preferences.lastOfferedUpdateVersion = release.version
        phase = .available
        window.show(activating: false)
    }

    /// Explicit "Check for Updates…" from the menu: always shows a result.
    func checkNow() async {
        if isInstalling { window.show(activating: true); return }
        guard !isChecking else { return }
        phase = .checking
        window.show(activating: true)
        guard let release = await fetchLatest() else {
            phase = .failed("Prompter couldn't reach GitHub. Check your connection and try again.")
            return
        }
        if ReleaseFeed.isNewer(release.version, than: currentVersion) {
            available = release
            preferences.lastOfferedUpdateVersion = release.version
            phase = .available
        } else {
            available = nil
            phase = .upToDate
        }
    }

    /// "Update to Prompter x.y.z…" in the menu.
    func showAvailable() {
        guard available != nil else { return }
        if !isInstalling { phase = .available }
        window.show(activating: true)
    }

    // MARK: - Installing

    func install() {
        guard let release = available, !isInstalling else { return }
        guard let url = release.downloadURL else {
            phase = .failed(UpdateInstaller.Failure.noDownload.localizedDescription)
            return
        }
        let installer = UpdateInstaller()
        phase = .downloading(received: 0, total: release.downloadSize)
        installTask = Task {
            do {
                let expected = try await installer.publishedChecksum(release.checksumURL)
                let download = try await installer.download(url, expectedBytes: release.downloadSize) { received, total in
                    Task { @MainActor in
                        if case .downloading = self.phase { self.phase = .downloading(received: received, total: total) }
                    }
                }
                phase = .verifying
                if let expected, expected != download.sha256 { throw UpdatePackage.VerificationError.checksumMismatch }
                let bundle = try await installer.unpack(zip: download.file)
                try await installer.verify(bundle: bundle, version: release.version)
                try Task.checkCancellation()
                phase = .installing
                try await installer.install(bundle: bundle)
                installer.cleanUp()
                phase = .restarting
                try? await Task.sleep(for: .milliseconds(900))
                if relaunchesAfterInstall { installer.relaunch() }
            } catch is CancellationError {
                installer.cleanUp()
                phase = .available
            } catch {
                installer.cleanUp()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Only honoured before anything on disk has changed; the view hides Cancel after that.
    func cancelInstall() {
        installTask?.cancel()
    }

    func retry() {
        if available != nil { install() } else { Task { await checkNow() } }
    }

    func skipThisVersion() {
        preferences.skippedUpdateVersion = available?.version
        available = nil
        phase = .idle
        window.close()
    }

    func later() {
        phase = .idle
        window.close()
    }

    func dismiss() {
        if !isInstalling { phase = .idle }
        window.close()
    }

    func windowDidClose() {
        if !isInstalling, !isChecking { phase = .idle }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(available?.pageURL ?? Self.releasesPage)
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

    // MARK: - Debug (`--snapshot-update`)

    func debugShow(phase: Phase, release: Release?) {
        available = release
        self.phase = phase
        window.show(activating: true)
    }

    var debugWindowContentView: NSView? { window.contentView }
}
