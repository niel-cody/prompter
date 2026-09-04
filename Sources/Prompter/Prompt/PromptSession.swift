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

/// The live state of one prompt: which script, where we are, how we're reading it, and
/// when the current phrase began (which is what the Pace Dot runs from).
/// UI observes this; engines (voice follow, keyboard) drive it.
@MainActor
@Observable
final class PromptSession {
    private(set) var script: PresentationScript
    private(set) var plan: PacePlan
    var title: String
    private(set) var currentIndex: Int = 0
    private(set) var style: DeliveryStyle = .professional
    var mode: ReadingMode = .coach

    /// Running means the clock is live and the Pace Dot moves.
    private(set) var isRunning = false
    /// When the speaker started the current phrase, or nil while paused / not started.
    private(set) var phraseStartedAt: Date?
    /// Time already spent on the current phrase before a pause, so resuming continues
    /// the dot from where it stopped instead of restarting the phrase.
    private var bankedPhraseTime: TimeInterval = 0

    private(set) var log = DeliveryLog()

    enum JumpSource { case user, voice }
    /// Fired after any position change; the voice follower re-anchors on user jumps.
    var onJump: ((Int, JumpSource) -> Void)?
    var onRunningChanged: ((Bool) -> Void)?
    /// The session ended (ran off the end of the script, or the user ended it).
    var onFinished: (() -> Void)?
    private let clock = ContinuousClock()
    private let origin = Date()

    init(script: PresentationScript, title: String, style: DeliveryStyle = .professional) {
        self.script = script
        self.title = title
        self.style = style
        self.plan = PacePlan(script: script, profile: style.profile)
    }

    // MARK: - Reading

    var currentPhrase: Phrase? { script.phrase(at: currentIndex) }
    var previousPhrase: Phrase? { script.phrase(at: currentIndex - 1) }
    var nextPhrase: Phrase? { script.phrase(at: currentIndex + 1) }
    var currentTiming: PhraseTiming? { plan.timing(at: currentIndex) }
    var isAtEnd: Bool { currentIndex >= script.phrases.count - 1 }
    var progress: Double {
        script.phrases.isEmpty ? 0 : Double(currentIndex) / Double(max(1, script.phrases.count - 1))
    }

    /// Seconds the speaker has spent on the current phrase, as of `date`.
    func phraseElapsed(at date: Date) -> TimeInterval {
        guard let start = phraseStartedAt else { return bankedPhraseTime }
        return bankedPhraseTime + date.timeIntervalSince(start)
    }

    func load(script: PresentationScript, title: String) {
        self.script = script
        self.title = title
        plan = PacePlan(script: script, profile: style.profile)
        reset()
    }

    func setStyle(_ style: DeliveryStyle) {
        self.style = style
        plan = PacePlan(script: script, profile: style.profile)
    }

    // MARK: - Clock

    func start() {
        guard !isRunning, !script.isEmpty else { return }
        let now = Date()
        // Starting again after a review begins a fresh session from wherever we are.
        if log.endedAt != nil {
            log = DeliveryLog()
            bankedPhraseTime = 0
        }
        isRunning = true
        if log.startedAt == nil {
            log.start(at: seconds(now))
            log.enter(phrase: currentIndex, at: seconds(now))
        } else {
            log.resume(at: seconds(now), phrase: currentIndex)
        }
        phraseStartedAt = now
        onRunningChanged?(true)
    }

    func pause() {
        guard isRunning else { return }
        let now = Date()
        bankedPhraseTime = phraseElapsed(at: now)
        phraseStartedAt = nil
        isRunning = false
        log.pause(at: seconds(now))
        onRunningChanged?(false)
    }

    func toggleRunning() { isRunning ? pause() : start() }

    func finish() {
        let now = Date()
        let wasRunning = isRunning
        isRunning = false
        phraseStartedAt = nil
        log.end(at: seconds(now))
        if wasRunning { onRunningChanged?(false) }
        onFinished?()
    }

    func reset() {
        let wasRunning = isRunning
        let moved = currentIndex != 0
        currentIndex = 0
        isRunning = false
        if wasRunning { onRunningChanged?(false) }
        phraseStartedAt = nil
        bankedPhraseTime = 0
        log = DeliveryLog()
        if moved { onJump?(0, .user) }
    }

    // MARK: - Navigation

    func jump(to index: Int, source: JumpSource = .user) {
        guard !script.isEmpty else { return }
        let clamped = min(max(0, index), script.phrases.count - 1)
        guard clamped != currentIndex else { return }
        currentIndex = clamped
        bankedPhraseTime = 0
        if isRunning {
            let now = Date()
            phraseStartedAt = now
            log.enter(phrase: clamped, at: seconds(now))
        }
        onJump?(clamped, source)
    }

    /// Voice follow heard new words.
    func noteSpeech() {
        guard isRunning else { return }
        log.noteSpeech(at: seconds(Date()))
    }

    func advance() {
        if isAtEnd { finish() } else { jump(to: currentIndex + 1) }
    }
    func retreat() { jump(to: currentIndex - 1) }
    func nextSection() {
        if let next = script.nextSectionStart(after: currentIndex) { jump(to: next) }
    }
    func previousSection() { jump(to: script.previousSectionStart(before: currentIndex)) }

    private func seconds(_ date: Date) -> TimeInterval { date.timeIntervalSince(origin) }
}
