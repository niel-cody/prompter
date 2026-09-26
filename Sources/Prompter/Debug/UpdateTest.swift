import AppKit
import SwiftUI
import PrompterCore

/// `Prompter --update-test <zip> [<target.app>]` runs the file-system half of an update
/// (unpack → verify → swap) against a scratch copy of the app and reports each step, so
/// the swap can be exercised without publishing a release or replacing the real install.
/// `Prompter --snapshot-update out.png` renders the update window in each of its states
/// to `out-<state>.png`.
@MainActor
enum UpdateTest {
    static func run(zipPath: String, targetPath: String?) {
        Task { @MainActor in
            let ok = await perform(zipPath: zipPath, targetPath: targetPath)
            exit(ok ? 0 : 1)
        }
    }

    private static func perform(zipPath: String, targetPath: String?) async -> Bool {
        let fm = FileManager.default
        let started = Date()
        func elapsed() -> String { String(format: "%.1fs", Date().timeIntervalSince(started)) }
        let target: URL
        if let targetPath {
            target = URL(fileURLWithPath: targetPath)
        } else {
            let scratch = fm.temporaryDirectory.appendingPathComponent("PrompterUpdateTest-\(UUID().uuidString)", isDirectory: true)
            try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            target = scratch.appendingPathComponent("Prompter.app")
            let copy = try? await UpdateInstaller.run("/usr/bin/ditto", [Bundle.main.bundleURL.path, target.path])
            guard copy?.status == 0 else { print("couldn't copy the app to \(target.path): \(copy?.output ?? "")"); return false }
        }
        func describe(_ id: UpdatePackage.BundleIdentity?) -> String {
            id.map { "\($0.version) (build \($0.build ?? "?"))" } ?? "unreadable"
        }
        print("target \(target.path)")
        print("  before: \(describe(UpdatePackage.identity(ofBundleAt: target)))")
        let installer = UpdateInstaller(appURL: target)
        do {
            let bundle = try await installer.unpack(zip: URL(fileURLWithPath: zipPath))
            guard let incoming = UpdatePackage.identity(ofBundleAt: bundle) else { print("FAILED: unpacked bundle unreadable"); return false }
            print("unpacked \(describe(incoming)) [\(elapsed())]")
            try await installer.verify(bundle: bundle, version: incoming.version)
            print("verified identity and signature [\(elapsed())]")
            try await installer.install(bundle: bundle)
            installer.cleanUp()
            let after = UpdatePackage.identity(ofBundleAt: target)
            print("installed; target now \(describe(after)) [\(elapsed())]")
            let leftovers = ((try? fm.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)) ?? [])
                .filter { $0.hasPrefix(".Prompter-") }
            print(leftovers.isEmpty ? "no leftovers in the folder" : "leftovers: \(leftovers)")
            let signed = try await UpdateInstaller.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", target.path])
            print(signed.status == 0 ? "installed copy passes codesign" : "installed copy FAILS codesign: \(signed.output)")
            let ok = after?.version == incoming.version && after?.build == incoming.build && leftovers.isEmpty && signed.status == 0
            print(ok ? "OK [\(elapsed())]" : "FAILED")
            if targetPath == nil { try? fm.removeItem(at: target.deletingLastPathComponent()) }
            return ok
        } catch {
            print("FAILED: \(error.localizedDescription)")
            installer.cleanUp()
            return false
        }
    }

    /// `--update-live`: the real thing against the real GitHub release, from whatever copy of
    /// the app this is (so run it from a scratch copy with an older version in its Info.plist).
    /// Checks, downloads, verifies and swaps, then reports instead of relaunching.
    static func runLive(checker: UpdateChecker) {
        checker.relaunchesAfterInstall = false
        Task { @MainActor in
            let app = Bundle.main.bundleURL
            print("running \(app.path) as \(checker.currentVersion)")
            let started = Date()
            await checker.checkNow()
            var last: UpdateChecker.Phase? = nil
            if checker.phase == .available {
                print("available: \(checker.available?.version ?? "?") (\(checker.available?.downloadSize ?? 0) bytes, checksum \(checker.available?.checksumURL == nil ? "none" : "published"))")
                checker.install()
            }
            while Date().timeIntervalSince(started) < 180 {
                if checker.phase != last {
                    last = checker.phase
                    print(String(format: "%5.1fs  ", Date().timeIntervalSince(started)) + "\(checker.phase)")
                }
                switch checker.phase {
                case .restarting, .upToDate, .failed, .idle:
                    let after = UpdatePackage.identity(ofBundleAt: app)
                    print("on disk now: \(after.map { "\($0.version) (build \($0.build ?? "?"))" } ?? "unreadable")")
                    let ok = checker.phase == .restarting && after?.version == checker.available?.version
                    print(checker.phase == .upToDate ? "nothing to update" : ok ? "OK" : "FAILED")
                    exit(ok || checker.phase == .upToDate ? 0 : 1)
                default:
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            print("timed out in \(checker.phase)")
            exit(1)
        }
    }

    static func snapshot(checker: UpdateChecker, outputPath: String) {
        let release = ReleaseInfo(
            version: "0.11.0",
            notes: "• In-app updates: one click downloads, checks and installs a new version, then reopens Prompter.\n• The update window says what it is doing at each step.\n• Releases now publish a checksum so a damaged download is never installed.",
            pageURL: URL(string: "https://github.com/niel-cody/prompter/releases/tag/v0.11.0")!,
            downloadURL: URL(string: "https://github.com/niel-cody/prompter/releases/download/v0.11.0/Prompter-0.11.0.zip"),
            checksumURL: nil, downloadSize: 2_097_542)
        let states: [(String, UpdateChecker.Phase, ReleaseInfo?)] = [
            ("checking", .checking, nil),
            ("available", .available, release),
            ("downloading", .downloading(received: 1_300_000, total: 2_097_542), release),
            ("installing", .installing, release),
            ("failed", .failed("The download stopped: The Internet connection appears to be offline."), release),
            ("uptodate", .upToDate, nil),
        ]
        let base = outputPath.hasSuffix(".png") ? String(outputPath.dropLast(4)) : outputPath
        Task { @MainActor in
            for (name, phase, release) in states {
                checker.debugShow(phase: phase, release: release)
                try? await Task.sleep(for: .milliseconds(700))
                let out = "\(base)-\(name).png"
                if let view = checker.debugWindowContentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: out))
                        print("written \(out) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                    }
                } else {
                    print("no window for \(name)")
                }
                // The window capture drops SwiftUI text offscreen; a second render through
                // ImageRenderer has the words (but no AppKit-backed buttons). Read both.
                let renderer = ImageRenderer(content: UpdateView(checker: checker))
                renderer.scale = 2
                if let cg = renderer.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "\(base)-\(name)-text.png"))
                    }
                }
            }
            NSApp.terminate(nil)
        }
    }
}
