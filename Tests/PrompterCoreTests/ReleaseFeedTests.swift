import Testing
import Foundation
@testable import PrompterCore

@Suite struct ReleaseFeedTests {
    /// Shaped like the real response from api.github.com/repos/niel-cody/prompter/releases/latest.
    func json(tag: String = "v0.9.1", draft: Bool = false, prerelease: Bool = false,
              assets: String = #"[{"name":"Prompter-0.9.1.zip","browser_download_url":"https://github.com/niel-cody/prompter/releases/download/v0.9.1/Prompter-0.9.1.zip"}]"#) -> Data {
        Data("""
        {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://github.com/niel-cody/prompter/releases/tag/\(tag)",
         "body":"Ready to demo.\\r\\n\\r\\n- **Universal** build\\r\\n- `--diagnose` flag\\r\\n",
         "assets":\(assets)}
        """.utf8)
    }

    @Test func readsVersionNotesAndDownload() {
        let r = ReleaseFeed.parseLatest(json())
        #expect(r?.version == "0.9.1")
        #expect(r?.downloadURL?.lastPathComponent == "Prompter-0.9.1.zip")
        #expect(r?.notes.contains("• Universal build") == true)
        #expect(r?.notes.contains("**") == false)
    }

    @Test func fallsBackToThePageWhenThereIsNoZip() {
        let r = ReleaseFeed.parseLatest(json(assets: "[]"))
        #expect(r?.downloadURL == nil)
        #expect(r?.pageURL.absoluteString.hasSuffix("v0.9.1") == true)
    }

    @Test func ignoresDraftsAndPrereleases() {
        #expect(ReleaseFeed.parseLatest(json(draft: true)) == nil)
        #expect(ReleaseFeed.parseLatest(json(prerelease: true)) == nil)
    }

    @Test func survivesRubbish() {
        #expect(ReleaseFeed.parseLatest(Data("not json".utf8)) == nil)
        #expect(ReleaseFeed.parseLatest(Data("{}".utf8)) == nil)
        #expect(ReleaseFeed.parseLatest(Data(#"{"tag_name":"v"}"#.utf8)) == nil)
    }

    @Test func versionComparison() {
        #expect(ReleaseFeed.isNewer("0.9.1", than: "0.9.0"))
        #expect(ReleaseFeed.isNewer("0.10.0", than: "0.9.9"))     // not string ordering
        #expect(ReleaseFeed.isNewer("1.0.0", than: "0.9.9"))
        #expect(ReleaseFeed.isNewer("1.2", than: "1.1.9"))
        #expect(!ReleaseFeed.isNewer("0.9.1", than: "0.9.1"))
        #expect(!ReleaseFeed.isNewer("1.2", than: "1.2.0"))        // 1.2 == 1.2.0
        #expect(!ReleaseFeed.isNewer("0.9.0", than: "0.9.1"))
        #expect(!ReleaseFeed.isNewer("0.9.0", than: "1.0.0"))
    }
}

@Suite struct ReleaseFeedChecksumTests {
    @Test func readsChecksumAndSize() {
        let data = Data("""
        {"tag_name":"v0.11.0","html_url":"https://github.com/niel-cody/prompter/releases/tag/v0.11.0","body":"",
         "assets":[{"name":"Prompter-0.11.0.zip","size":2097542,"browser_download_url":"https://example.com/Prompter-0.11.0.zip"},
                   {"name":"Prompter-0.11.0.zip.sha256","size":85,"browser_download_url":"https://example.com/Prompter-0.11.0.zip.sha256"}]}
        """.utf8)
        let r = ReleaseFeed.parseLatest(data)
        #expect(r?.downloadURL?.lastPathComponent == "Prompter-0.11.0.zip")
        #expect(r?.checksumURL?.lastPathComponent == "Prompter-0.11.0.zip.sha256")
        #expect(r?.downloadSize == 2_097_542)
    }

    @Test func olderReleasesHaveNoChecksum() {
        let data = Data("""
        {"tag_name":"v0.10.0","html_url":"https://github.com/x/y/releases/tag/v0.10.0","body":"",
         "assets":[{"name":"Prompter-0.10.0.zip","browser_download_url":"https://example.com/Prompter-0.10.0.zip"}]}
        """.utf8)
        let r = ReleaseFeed.parseLatest(data)
        #expect(r?.downloadURL != nil)
        #expect(r?.checksumURL == nil)
        #expect(r?.downloadSize == nil)
    }
}
