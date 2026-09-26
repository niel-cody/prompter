import AppKit
import CryptoKit
import Foundation
import PrompterCore

/// Puts a downloaded release in place of the running app: download, check, unpack, swap the
/// bundle, relaunch. Each step is its own method so `UpdateChecker` can narrate progress and
/// `--update-test` can run the file-system half against a scratch copy of the app.
///
/// The swap is two renames inside the app's own folder (old → hidden backup, new → app), so
/// Launch Services never sees a half-copied bundle and the second rename failing puts the old
/// copy straight back. If the folder isn't writable by this account, the same steps run once
/// with administrator privileges through the standard macOS password prompt.
struct UpdateInstaller: Sendable {
    enum Failure: Error, LocalizedError {
        case noDownload
        case badResponse(Int)
        case network(String)
        case unzipFailed(String)
        case signatureInvalid(String)
        case translocated
        case swapFailed(String)
        case authorisationDeclined

        var errorDescription: String? {
            switch self {
            case .noDownload: "This release has nothing to download yet."
            case .badResponse(let code): "GitHub answered with an error (HTTP \(code))."
            case .network(let detail): "The download stopped: \(detail)"
            case .unzipFailed: "The download couldn't be unpacked."
            case .signatureInvalid: "The downloaded copy of Prompter failed its signature check, so it wasn't installed."
            case .translocated: "Prompter is running from a temporary location. Move it into Applications and try again."
            case .swapFailed(let detail): "The new version couldn't be put in place: \(detail)"
            case .authorisationDeclined: "The update needs an administrator's permission to change the Applications folder."
            }
        }
    }

    struct Download: Sendable {
        let file: URL
        let sha256: String
        let bytes: Int64
    }

    struct CommandResult: Sendable {
        let status: Int32
        let output: String
    }

    /// The bundle being replaced. Normally the running app.
    let appURL: URL
    let identifier: String
    /// Scratch space for the zip and the unpacked bundle; removed by `cleanUp()`.
    let workDirectory: URL

    init(appURL: URL = Bundle.main.bundleURL,
         identifier: String = Bundle.main.bundleIdentifier ?? "com.nielcody.prompter") {
        self.appURL = appURL.standardizedFileURL
        self.identifier = identifier
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrompterUpdate-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - Download

    /// The SHA-256 the release publishes for its zip, or nil when the release predates
    /// checksums (before 0.11) and there is nothing to compare against.
    func publishedChecksum(_ url: URL?) async throws -> String? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let code = (response as? HTTPURLResponse)?.statusCode, code == 200 else {
                throw Failure.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            return UpdatePackage.parseChecksum(String(decoding: data, as: UTF8.self))
        } catch let error as URLError {
            throw Failure.network(error.localizedDescription)
        }
    }

    /// Fetches the release zip into the work folder, hashing it on the way. `progress` is
    /// called off the main thread with the bytes so far and the total when it's known.
    func download(_ url: URL, expectedBytes: Int64?,
                  progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> Download {
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let name = url.lastPathComponent.hasSuffix(".zip") ? url.lastPathComponent : "Prompter.zip"
        let file = workDirectory.appendingPathComponent(name)
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Prompter", forHTTPHeaderField: "User-Agent")
        return try await Task.detached(priority: .userInitiated) { () throws -> Download in
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw Failure.network("no response") }
                guard http.statusCode == 200 else { throw Failure.badResponse(http.statusCode) }
                let total = http.expectedContentLength > 0 ? http.expectedContentLength : expectedBytes
                guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
                    throw Failure.swapFailed("couldn't write to \(file.deletingLastPathComponent().path)")
                }
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                var hasher = SHA256()
                var chunk = Data(capacity: 256 * 1024)
                var received: Int64 = 0
                for try await byte in bytes {
                    chunk.append(byte)
                    if chunk.count >= 256 * 1024 {
                        try handle.write(contentsOf: chunk)
                        hasher.update(data: chunk)
                        received += Int64(chunk.count)
                        chunk.removeAll(keepingCapacity: true)
                        progress(received, total)
                    }
                }
                if !chunk.isEmpty {
                    try handle.write(contentsOf: chunk)
                    hasher.update(data: chunk)
                    received += Int64(chunk.count)
                }
                progress(received, total ?? received)
                let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
                return Download(file: file, sha256: digest, bytes: received)
            } catch let error as URLError {
                throw Failure.network(error.localizedDescription)
            }
        }.value
    }

    // MARK: - Unpack and verify

    /// Unzips the download and returns the `Prompter.app` inside it.
    func unpack(zip: URL) async throws -> URL {
        let dir = workDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let result = try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        guard result.status == 0 else { throw Failure.unzipFailed(result.output) }
        guard let bundle = UpdatePackage.bundle(inUnpackedDirectory: dir) else {
            throw UpdatePackage.VerificationError.missingBundle
        }
        return bundle
    }

    /// The unpacked bundle is Prompter, at the promised version, with an intact signature.
    func verify(bundle: URL, version: String) async throws {
        try UpdatePackage.verify(bundleAt: bundle, identifier: identifier, version: version)
        let result = try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle.path])
        guard result.status == 0 else { throw Failure.signatureInvalid(result.output) }
    }

    // MARK: - Swap

    /// Replaces `appURL` with the verified bundle. The old copy is renamed aside first and
    /// put back if the new one can't be moved in.
    func install(bundle staged: URL) async throws {
        if appURL.path.contains("/AppTranslocation/") { throw Failure.translocated }
        let parent = appURL.deletingLastPathComponent()
        let tag = String(UUID().uuidString.prefix(8))
        let incoming = parent.appendingPathComponent(".Prompter-\(tag)-new.app")
        let backup = parent.appendingPathComponent(".Prompter-\(tag)-old.app")

        if FileManager.default.isWritableFile(atPath: parent.path) {
            do {
                try await swap(staged: staged, incoming: incoming, backup: backup)
                return
            } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                // Fall through to the privileged path.
            } catch let error as Failure {
                throw error
            } catch {
                throw Failure.swapFailed(error.localizedDescription)
            }
        }
        try await swapWithAdministratorPrivileges(staged: staged, incoming: incoming, backup: backup)
    }

    private func swap(staged: URL, incoming: URL, backup: URL) async throws {
        let fm = FileManager.default
        let copy = try await Self.run("/usr/bin/ditto", [staged.path, incoming.path])
        guard copy.status == 0 else {
            try? fm.removeItem(at: incoming)
            throw Failure.swapFailed(copy.output)
        }
        // Nothing here was downloaded by a browser, but be certain Gatekeeper has no reason
        // to hold the new copy at arm's length.
        _ = try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", incoming.path])
        do {
            try fm.moveItem(at: appURL, to: backup)
        } catch {
            try? fm.removeItem(at: incoming)
            throw error
        }
        do {
            try fm.moveItem(at: incoming, to: appURL)
        } catch {
            try? fm.moveItem(at: backup, to: appURL)
            try? fm.removeItem(at: incoming)
            throw Failure.swapFailed(error.localizedDescription)
        }
        // Best effort: a root-owned old copy can't be removed by us and is swept next launch.
        try? fm.removeItem(at: backup)
    }

    private func swapWithAdministratorPrivileges(staged: URL, incoming: URL, backup: URL) async throws {
        func q(_ url: URL) -> String { "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = """
        #!/bin/sh
        set -e
        /usr/bin/ditto \(q(staged)) \(q(incoming))
        /usr/bin/xattr -dr com.apple.quarantine \(q(incoming)) 2>/dev/null || true
        /usr/sbin/chown -R \(getuid()):\(getgid()) \(q(incoming))
        /bin/mv \(q(appURL)) \(q(backup))
        if ! /bin/mv \(q(incoming)) \(q(appURL)); then /bin/mv \(q(backup)) \(q(appURL)); /bin/rm -rf \(q(incoming)); exit 1; fi
        /bin/rm -rf \(q(backup))
        """
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let scriptURL = workDirectory.appendingPathComponent("install.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        let escaped = scriptURL.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let apple = "do shell script (\"/bin/sh \" & quoted form of \"\(escaped)\") with administrator privileges"
        let result = try await Self.run("/usr/bin/osascript", ["-e", apple])
        guard result.status == 0 else {
            if result.output.contains("-128") { throw Failure.authorisationDeclined }
            throw Failure.swapFailed(result.output)
        }
    }

    // MARK: - Relaunch and housekeeping

    /// Quits this copy and opens the one now at `appURL` once it has fully gone, so the
    /// single-instance guard in the new copy doesn't hand back to a dying process.
    @MainActor
    func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = "'" + appURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(path)"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
        NSApp.terminate(nil)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: workDirectory)
    }

    /// Removes hidden copies an earlier update couldn't delete (an old copy owned by root,
    /// or a new one orphaned by a crash mid-swap). Called at launch, when nothing is in flight.
    func sweepLeftovers() {
        let parent = appURL.deletingLastPathComponent()
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        for name in entries where name.hasPrefix(".Prompter-") && (name.hasSuffix("-old.app") || name.hasSuffix("-new.app")) {
            try? FileManager.default.removeItem(at: parent.appendingPathComponent(name))
        }
    }

    /// Runs a command line tool to completion off the main thread.
    static func run(_ tool: String, _ arguments: [String]) async throws -> CommandResult {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandResult(status: process.terminationStatus, output: output)
        }.value
    }
}
