import Foundation

/// A release published on GitHub, as far as the in-app update check cares.
public struct ReleaseInfo: Sendable, Equatable {
    public let version: String
    public let notes: String
    public let pageURL: URL
    public let downloadURL: URL?

    public init(version: String, notes: String, pageURL: URL, downloadURL: URL?) {
        self.version = version
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }
}

/// Parsing and version comparison for the update check. Pure, and tested: a bug here means
/// people either never hear about an update or are pestered about one they already have.
public enum ReleaseFeed {
    /// Reads GitHub's `releases/latest` response.
    public static func parseLatest(_ data: Data) -> ReleaseInfo? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }
        // Drafts and prereleases are not offered to people.
        if json["draft"] as? Bool == true || json["prerelease"] as? Bool == true { return nil }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty else { return nil }
        let body = (json["body"] as? String ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
        let download = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:))
        return ReleaseInfo(version: version, notes: plainNotes(body), pageURL: page, downloadURL: download)
    }

    /// Markdown release notes rendered as plain text, for an alert.
    public static func plainNotes(_ markdown: String) -> String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var s = String(line)
                s = s.replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "• ", options: .regularExpression)
                s = s.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
                s = s.replacingOccurrences(of: #"(\*\*|__|`)"#, with: "", options: .regularExpression)
                return s
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Compares dotted numeric versions. Missing components count as zero, so 1.2 == 1.2.0.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func components(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
}
