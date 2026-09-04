import Foundation

/// What actually happened during a presentation, phrase by phrase. The delivery review is
/// computed from this after the session; nothing here is shown live.
public struct DeliveryLog: Sendable, Equatable {
    public struct Visit: Sendable, Equatable {
        public let phraseIndex: Int
        public let enteredAt: TimeInterval
        public var leftAt: TimeInterval?

        public var duration: TimeInterval? { leftAt.map { $0 - enteredAt } }
    }

    public private(set) var visits: [Visit] = []
    public private(set) var startedAt: TimeInterval?
    public private(set) var endedAt: TimeInterval?
    /// Total time the session was paused, excluded from pace calculations.
    public private(set) var pausedDuration: TimeInterval = 0
    private var pauseBegan: TimeInterval?

    public init() {}

    public mutating func start(at t: TimeInterval) {
        startedAt = t
        endedAt = nil
    }

    public mutating func enter(phrase index: Int, at t: TimeInterval) {
        if let last = visits.indices.last, visits[last].leftAt == nil {
            visits[last].leftAt = t
        }
        visits.append(Visit(phraseIndex: index, enteredAt: t, leftAt: nil))
    }

    public mutating func pause(at t: TimeInterval) {
        guard pauseBegan == nil else { return }
        pauseBegan = t
        if let last = visits.indices.last, visits[last].leftAt == nil {
            visits[last].leftAt = t
        }
    }

    public mutating func resume(at t: TimeInterval, phrase index: Int) {
        if let began = pauseBegan {
            pausedDuration += t - began
            pauseBegan = nil
        }
        visits.append(Visit(phraseIndex: index, enteredAt: t, leftAt: nil))
    }

    public mutating func end(at t: TimeInterval) {
        if let last = visits.indices.last, visits[last].leftAt == nil {
            visits[last].leftAt = t
        }
        if let began = pauseBegan {
            pausedDuration += t - began
            pauseBegan = nil
        }
        endedAt = t
    }

    public var activeDuration: TimeInterval? {
        guard let s = startedAt, let e = endedAt else { return nil }
        return e - s - pausedDuration
    }

    /// Highest phrase index the speaker reached.
    public var furthestPhrase: Int? { visits.map(\.phraseIndex).max() }
}
