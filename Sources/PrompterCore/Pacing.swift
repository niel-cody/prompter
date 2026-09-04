import Foundation

/// How the speaker wants to come across. Presets are the primary control; WPM is a
/// consequence, not a setting the user has to reason about.
public enum DeliveryStyle: String, Sendable, Codable, CaseIterable, Identifiable {
    case measured
    case professional
    case conversational
    case energetic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .measured: "Measured"
        case .professional: "Professional"
        case .conversational: "Conversational"
        case .energetic: "Energetic"
        }
    }

    public var summary: String {
        switch self {
        case .measured: "Slow and deliberate. Room around every point."
        case .professional: "Calm, confident, boardroom pace."
        case .conversational: "Relaxed and natural, like talking to a colleague."
        case .energetic: "Brisk and upbeat. Keeps a demo moving."
        }
    }

    public var profile: PacingProfile {
        switch self {
        case .measured:
            PacingProfile(wordsPerMinute: 120, pauseScale: 1.35)
        case .professional:
            PacingProfile(wordsPerMinute: 140, pauseScale: 1.0)
        case .conversational:
            PacingProfile(wordsPerMinute: 155, pauseScale: 0.8)
        case .energetic:
            PacingProfile(wordsPerMinute: 170, pauseScale: 0.65)
        }
    }
}

/// Timing parameters derived from a delivery style.
public struct PacingProfile: Sendable, Equatable {
    public var wordsPerMinute: Double
    /// Multiplies every suggested pause.
    public var pauseScale: Double
    /// Strong phrases are delivered a little slower.
    public var emphasisSlowdown: Double = 1.15

    public init(wordsPerMinute: Double, pauseScale: Double) {
        self.wordsPerMinute = wordsPerMinute
        self.pauseScale = pauseScale
    }

    public var secondsPerWord: TimeInterval { 60 / wordsPerMinute }

    /// Base pause lengths at pauseScale 1.0 (Professional).
    public func pauseDuration(_ kind: PauseKind) -> TimeInterval {
        let base: TimeInterval
        switch kind {
        case .none: base = 0
        case .beat: base = 0.25
        case .clause: base = 0.40
        case .sentence: base = 0.70
        case .emphatic: base = 1.00
        case .paragraph: base = 1.40
        }
        return base * pauseScale
    }

    /// How long a phrase should take to say, excluding the pause after it.
    public func speakingDuration(of phrase: Phrase) -> TimeInterval {
        var seconds = Double(phrase.words.count) * secondsPerWord
        // Longer words take longer to say. Cheap syllable proxy: characters over 6.
        let extraChars = phrase.words.reduce(0) { $0 + max(0, $1.normalized.count - 6) }
        seconds += Double(extraChars) * secondsPerWord * 0.12
        if phrase.emphasis == .strong { seconds *= emphasisSlowdown }
        return seconds
    }

    /// Speaking time plus the suggested pause after the phrase.
    public func totalDuration(of phrase: Phrase) -> TimeInterval {
        speakingDuration(of: phrase) + pauseDuration(phrase.pauseAfter)
    }

    public func estimatedDuration(of script: PresentationScript) -> TimeInterval {
        script.phrases.reduce(0) { $0 + totalDuration(of: $1) }
    }
}
