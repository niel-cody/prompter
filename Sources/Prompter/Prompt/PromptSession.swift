import Foundation
import Observation
import PrompterCore

enum ReadingMode: String, CaseIterable, Identifiable, Codable {
    case coach
    case classic
    case manual

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .coach: "Coach"
        case .classic: "Classic"
        case .manual: "Manual"
        }
    }
}

/// The live state of one prompt: which script, where we are, how we're reading it.
/// UI observes this; engines (pace, voice follow) drive it.
@MainActor
@Observable
final class PromptSession {
    private(set) var script: PresentationScript
    var title: String
    private(set) var currentIndex: Int = 0
    var style: DeliveryStyle = .professional
    var mode: ReadingMode = .coach
    var isRunning = false

    init(script: PresentationScript, title: String) {
        self.script = script
        self.title = title
    }

    var currentPhrase: Phrase? { script.phrase(at: currentIndex) }
    var previousPhrase: Phrase? { script.phrase(at: currentIndex - 1) }
    var nextPhrase: Phrase? { script.phrase(at: currentIndex + 1) }
    var isAtEnd: Bool { currentIndex >= script.phrases.count - 1 }
    var progress: Double {
        script.phrases.isEmpty ? 0 : Double(currentIndex) / Double(max(1, script.phrases.count - 1))
    }

    func load(script: PresentationScript, title: String) {
        self.script = script
        self.title = title
        currentIndex = 0
        isRunning = false
    }

    func jump(to index: Int) {
        guard !script.isEmpty else { return }
        currentIndex = min(max(0, index), script.phrases.count - 1)
    }

    func advance() { jump(to: currentIndex + 1) }
    func retreat() { jump(to: currentIndex - 1) }
    func nextSection() {
        if let next = script.nextSectionStart(after: currentIndex) { jump(to: next) }
    }
    func previousSection() { jump(to: script.previousSectionStart(before: currentIndex)) }
    func restart() { jump(to: 0); isRunning = false }
}
