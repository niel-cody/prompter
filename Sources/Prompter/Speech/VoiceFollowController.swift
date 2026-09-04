import Foundation
import Observation
import PrompterCore

/// Glue between recognised speech and the prompt: normalises the transcript, asks the
/// matcher where we are, and moves the session when the matcher is confident.
@MainActor
@Observable
final class VoiceFollowController {
    let speech = SpeechService()
    private(set) var isEnabled = true
    /// Most recent transcript text, for the debug overlay / logs.
    private(set) var latestTranscript = ""

    private weak var session: PromptSession?
    private var matcher: ScriptMatcher?
    private var committedTokens: [String] = []
    private var volatileTokens: [String] = []
    private var lastReportedTokenCount = 0
    /// Once the last phrase has been spoken, a few quiet seconds end the session on their own.
    private var autoFinish: Task<Void, Never>?
    private let autoFinishDelay: Duration = .seconds(3)

    init() {
        speech.onTranscript = { [weak self] update in self?.handle(update) }
    }

    func attach(to session: PromptSession) {
        self.session = session
        rebuildMatcher()
    }

    /// Call when the script or the reading position changes for any reason other than voice.
    func rebuildMatcher() {
        guard let session else { return }
        var m = ScriptMatcher(script: session.script)
        m.reset(toPhrase: session.currentIndex)
        matcher = m
        committedTokens.removeAll()
        volatileTokens.removeAll()
        lastReportedTokenCount = 0
        latestTranscript = ""
        speech.contextualVocabulary = Self.vocabulary(of: session.script)
    }

    func reanchor(toPhrase phrase: Int) {
        matcher?.reset(toPhrase: phrase)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { stopListening() } else if session?.isRunning == true { startListening() }
    }

    /// `--transcript` on the command line logs what was heard and every move it caused.
    static let logsTranscript = CommandLine.arguments.contains("--transcript")

    func startListening() {
        guard isEnabled else { return }
        Task { await speech.start() }
    }

    func stopListening() {
        autoFinish?.cancel()
        speech.stop()
    }

    private func handle(_ update: TranscriptUpdate) {
        let tokens = TextNormalizer.tokens(from: update.text)
        if update.isFinal {
            committedTokens.append(contentsOf: tokens)
            volatileTokens.removeAll()
            // Keep memory bounded; the matcher only ever looks at the tail.
            if committedTokens.count > 400 { committedTokens.removeFirst(committedTokens.count - 400) }
        } else {
            volatileTokens = tokens
        }
        latestTranscript = update.text
        let all = committedTokens + volatileTokens
        guard let session, var matcher, !all.isEmpty else { return }

        if all.count != lastReportedTokenCount {
            lastReportedTokenCount = all.count
            session.noteSpeech()
        }

        let result = matcher.update(spoken: all)
        self.matcher = matcher
        if Self.logsTranscript {
            NSLog("[voice] %@ %@%@", update.isFinal ? "FINAL" : "vol  ", update.text,
                  result.map { " → phrase \($0.phraseIndex) score \(String(format: "%.1f", $0.score))" } ?? "")
        }
        if let result, result.phraseIndex != session.currentIndex {
            session.jump(to: result.phraseIndex, source: .voice)
        }

        autoFinish?.cancel()
        if let result, result.atPhraseEnd, result.phraseIndex == session.script.phrases.count - 1, session.isRunning {
            autoFinish = Task { [weak self, delay = autoFinishDelay] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, let session = self.session, session.isRunning else { return }
                session.finish()
            }
        }
    }

    /// Distinct content words of the script, for biasing recognition.
    static func vocabulary(of script: PresentationScript) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for phrase in script.phrases {
            for word in phrase.words where word.normalized.count >= 4 && !TextNormalizer.stopWords.contains(word.normalized) {
                let display = word.text.trimmingCharacters(in: .punctuationCharacters)
                if seen.insert(word.normalized).inserted { out.append(display) }
            }
        }
        return Array(out.prefix(300))
    }
}
