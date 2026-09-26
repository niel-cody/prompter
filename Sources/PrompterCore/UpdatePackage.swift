import Foundation

/// The parts of installing an update that can be checked without AppKit: what a checksum
/// file says, and whether an unpacked bundle is really the Prompter we were promised.
/// The installer itself (download, unzip, swap, relaunch) lives in the app.
public enum UpdatePackage {
    public enum VerificationError: Error, Equatable, LocalizedError {
        case missingBundle
        case unreadableInfoPlist
        case wrongIdentifier(found: String)
        case wrongVersion(found: String, expected: String)
        case checksumMismatch

        public var errorDescription: String? {
            switch self {
            case .missingBundle: return "The download didn't contain Prompter."
            case .unreadableInfoPlist: return "The downloaded copy of Prompter is incomplete."
            case .wrongIdentifier(let found): return "The download is a different app (\(found))."
            case .wrongVersion(let found, let expected): return "The download is Prompter \(found), not \(expected)."
            case .checksumMismatch: return "The download was damaged on the way here."
            }
        }
    }

    /// Identity read from a bundle's Info.plist.
    public struct BundleIdentity: Equatable, Sendable {
        public let identifier: String
        public let version: String
        public let build: String?
    }

    /// Reads the identity of the app bundle at `url`, or nil if it isn't a readable bundle.
    public static func identity(ofBundleAt url: URL) -> BundleIdentity? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String,
              let version = dict["CFBundleShortVersionString"] as? String
        else { return nil }
        return BundleIdentity(identifier: id, version: version, build: dict["CFBundleVersion"] as? String)
    }

    /// Confirms the bundle at `url` is Prompter at the version the release promised.
    public static func verify(bundleAt url: URL, identifier: String, version: String) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw VerificationError.missingBundle
        }
        guard let identity = identity(ofBundleAt: url) else { throw VerificationError.unreadableInfoPlist }
        guard identity.identifier == identifier else { throw VerificationError.wrongIdentifier(found: identity.identifier) }
        guard !ReleaseFeed.isNewer(version, than: identity.version), !ReleaseFeed.isNewer(identity.version, than: version) else {
            throw VerificationError.wrongVersion(found: identity.version, expected: version)
        }
    }

    /// The hex digest in a `.sha256` file, whether it's bare or in `shasum` format
    /// ("<hex>  Prompter-1.2.3.zip"). Nil if there isn't one.
    public static func parseChecksum(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard let token = line.split(whereSeparator: \.isWhitespace).first else { continue }
            let hex = token.lowercased()
            if hex.count == 64, hex.allSatisfy(\.isHexDigit) { return hex }
        }
        return nil
    }

    /// Path of the app bundle inside an unpacked release, given the folder it was unzipped
    /// into. The zip is built with `--keepParent`, so it's `<dir>/Prompter.app`; but be
    /// forgiving about a single wrapping folder.
    public static func bundle(inUnpackedDirectory dir: URL, named name: String = "Prompter.app") -> URL? {
        let direct = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.hasDirectoryPath {
            let nested = entry.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }
}
