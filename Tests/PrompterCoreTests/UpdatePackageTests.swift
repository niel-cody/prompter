import Testing
import Foundation
@testable import PrompterCore

@Suite struct UpdatePackageTests {
    /// A throwaway folder with a fake `Prompter.app` inside, shaped like the real bundle.
    func fakeBundle(identifier: String = "com.nielcody.prompter", version: String = "0.11.0",
                    wrappedIn folder: String? = nil) throws -> (root: URL, app: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UpdatePackageTests-\(UUID().uuidString)")
        var app = root
        if let folder { app = app.appendingPathComponent(folder) }
        app = app.appendingPathComponent("Prompter.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version, "CFBundleVersion": "7"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return (root, app)
    }

    @Test func readsIdentity() throws {
        let (root, app) = try fakeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UpdatePackage.identity(ofBundleAt: app)
        #expect(id == .init(identifier: "com.nielcody.prompter", version: "0.11.0", build: "7"))
        #expect(UpdatePackage.identity(ofBundleAt: root) == nil)
    }

    @Test func verifiesTheRightApp() throws {
        let (root, app) = try fakeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        try UpdatePackage.verify(bundleAt: app, identifier: "com.nielcody.prompter", version: "0.11.0")
        // 0.11 and 0.11.0 are the same version.
        try UpdatePackage.verify(bundleAt: app, identifier: "com.nielcody.prompter", version: "0.11")
    }

    @Test func rejectsTheWrongApp() throws {
        let (root, app) = try fakeBundle(identifier: "com.example.other")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: UpdatePackage.VerificationError.wrongIdentifier(found: "com.example.other")) {
            try UpdatePackage.verify(bundleAt: app, identifier: "com.nielcody.prompter", version: "0.11.0")
        }
    }

    @Test func rejectsTheWrongVersion() throws {
        let (root, app) = try fakeBundle(version: "0.10.0")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: UpdatePackage.VerificationError.wrongVersion(found: "0.10.0", expected: "0.11.0")) {
            try UpdatePackage.verify(bundleAt: app, identifier: "com.nielcody.prompter", version: "0.11.0")
        }
    }

    @Test func rejectsMissingOrBrokenBundles() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).app")
        #expect(throws: UpdatePackage.VerificationError.missingBundle) {
            try UpdatePackage.verify(bundleAt: missing, identifier: "x", version: "1")
        }
        let (root, app) = try fakeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/Info.plist"))
        #expect(throws: UpdatePackage.VerificationError.unreadableInfoPlist) {
            try UpdatePackage.verify(bundleAt: app, identifier: "x", version: "1")
        }
    }

    @Test func findsTheBundleInAnUnpackedZip() throws {
        let (root, app) = try fakeBundle()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(UpdatePackage.bundle(inUnpackedDirectory: root)?.resolvingSymlinksInPath().path == app.resolvingSymlinksInPath().path)
        let (root2, app2) = try fakeBundle(wrappedIn: "Prompter-0.11.0")
        defer { try? FileManager.default.removeItem(at: root2) }
        #expect(UpdatePackage.bundle(inUnpackedDirectory: root2)?.resolvingSymlinksInPath().path == app2.resolvingSymlinksInPath().path)
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(UpdatePackage.bundle(inUnpackedDirectory: empty) == nil)
    }

    @Test func parsesChecksums() {
        let hex = String(repeating: "ab", count: 32)
        #expect(UpdatePackage.parseChecksum(hex) == hex)
        #expect(UpdatePackage.parseChecksum("\(hex.uppercased())  Prompter-0.11.0.zip\n") == hex)
        #expect(UpdatePackage.parseChecksum("# comment\n\(hex) *Prompter.zip") == hex)
        #expect(UpdatePackage.parseChecksum("deadbeef") == nil)
        #expect(UpdatePackage.parseChecksum("") == nil)
        #expect(UpdatePackage.parseChecksum(String(repeating: "zz", count: 32)) == nil)
    }
}
