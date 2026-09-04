import Foundation

/// Ideal timing for one phrase under a given delivery style.
public struct PhraseTiming: Sendable, Equatable {
    public let phraseIndex: Int
    /// How long the phrase should take to say.
    public let speaking: TimeInterval
    /// The suggested pause after it.
    public let pause: TimeInterval

    public init(phraseIndex: Int, speaking: TimeInterval, pause: TimeInterval) {
        self.phraseIndex = phraseIndex
        self.speaking = speaking
        self.pause = pause
    }

    public var total: TimeInterval { speaking + pause }
}

/// The ideal timeline for a whole script. This is guidance for the Pace Dot and the
/// review, never something that moves the prompt on its own.
public struct PacePlan: Sendable, Equatable {
    public let timings: [PhraseTiming]
    public let profile: PacingProfile

    public init(script: PresentationScript, profile: PacingProfile) {
        self.profile = profile
        timings = script.phrases.map {
            PhraseTiming(phraseIndex: $0.id,
                         speaking: profile.speakingDuration(of: $0),
                         pause: profile.pauseDuration($0.pauseAfter))
        }
    }

    public func timing(at index: Int) -> PhraseTiming? {
        timings.indices.contains(index) ? timings[index] : nil
    }

    public var totalDuration: TimeInterval { timings.reduce(0) { $0 + $1.total } }
}

/// Where the conductor is within the current phrase.
public enum PacePhase: Sendable, Equatable {
    /// Moving through the words. `progress` runs 0...1 across the phrase.
    case speaking(progress: Double)
    /// Holding at the end of the phrase for the suggested pause. `progress` runs 0...1.
    case pausing(progress: Double)
    /// The speaker has held longer than suggested. That may be deliberate; the dot just
    /// waits quietly.
    case waiting(for: TimeInterval)

    public var isSpeaking: Bool {
        if case .speaking = self { return true }
        return false
    }
}

public enum PaceConductor {
    /// The conductor's position `elapsed` seconds after the speaker started the phrase.
    public static func phase(elapsed: TimeInterval, timing: PhraseTiming) -> PacePhase {
        let e = max(0, elapsed)
        if timing.speaking > 0, e < timing.speaking {
            return .speaking(progress: e / timing.speaking)
        }
        let intoPause = e - timing.speaking
        if timing.pause > 0, intoPause < timing.pause {
            return .pausing(progress: intoPause / timing.pause)
        }
        return .waiting(for: intoPause - timing.pause)
    }
}
