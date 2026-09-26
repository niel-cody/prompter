import AppKit
import Foundation

/// "Send Feedback…" for beta testers: opens their mail app with a message to Niel already
/// addressed, a subject with the version, and the facts we always end up asking for
/// (version, macOS, Mac) filled in at the bottom. They write what happened and press send.
@MainActor
enum FeedbackComposer {
    /// Where feedback goes. Change this in one place if it should go somewhere else.
    static let address = "niel.cody@oolio.com"

    static func send() {
        guard let url = mailURL() else { return }
        NSWorkspace.shared.open(url)
    }

    static func mailURL() -> URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let body = """
        Hi Niel,

        What I was doing:

        What happened:

        What I expected:



        ---
        \(Diagnostics.summary())
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Prompter \(version) feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
