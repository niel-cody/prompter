import Foundation

/// The internal, presentation-ready form of a script.
///
/// The user's original text is kept verbatim in `sourceText`; everything else is derived
/// metadata (phrases, pauses, emphasis) and can be regenerated at any time without touching
/// what the user wrote.
public struct PresentationScript: Sendable, Equatable {
    public let sourceText: String
    public let sections: [Section]
    public let phrases: [Phrase]

    public init(sourceText: String, sections: [Section], phrases: [Phrase]) {
        self.sourceText = sourceText
        self.sections = sections
        self.phrases = phrases
    }

    public var wordCount: Int { phrases.reduce(0) { $0 + $1.words.count } }
    public var isEmpty: Bool { phrases.isEmpty }

    public func phrase(at index: Int) -> Phrase? {
        phrases.indices.contains(index) ? phrases[index] : nil
    }

    /// Index of the first phrase of the section that contains `phraseIndex`.
    public func sectionStart(containing phraseIndex: Int) -> Int {
        guard let phrase = phrase(at: phraseIndex) else { return 0 }
        return sections[phrase.sectionIndex].phraseRange.lowerBound
    }

    /// Index of the first phrase of the next section, or nil at the end.
    public func nextSectionStart(after phraseIndex: Int) -> Int? {
        guard let phrase = phrase(at: phraseIndex) else { return nil }
        let next = phrase.sectionIndex + 1
        return sections.indices.contains(next) ? sections[next].phraseRange.lowerBound : nil
    }

    /// Index of the first phrase of the previous section (or the start of this one if we're
    /// not already at its first phrase), mirroring how "previous track" works in a music app.
    public func previousSectionStart(before phraseIndex: Int) -> Int {
        let start = sectionStart(containing: phraseIndex)
        if start < phraseIndex { return start }
        guard let phrase = phrase(at: phraseIndex), phrase.sectionIndex > 0 else { return 0 }
        return sections[phrase.sectionIndex - 1].phraseRange.lowerBound
    }
}

/// A paragraph of the source text.
public struct Section: Sendable, Equatable {
    public let index: Int
    public let phraseRange: Range<Int>

    public init(index: Int, phraseRange: Range<Int>) {
        self.index = index
        self.phraseRange = phraseRange
    }
}

/// One spoken unit: roughly a breath's worth of words. This is what the prompt highlights.
public struct Phrase: Sendable, Equatable, Identifiable {
    /// Ordinal position in the script. Stable for the life of a `PresentationScript`.
    public let id: Int
    public let text: String
    public let words: [Word]
    public let sectionIndex: Int
    public let sentenceIndex: Int
    public let isSentenceStart: Bool
    public let isSentenceEnd: Bool
    public let pauseAfter: PauseKind
    public let emphasis: Emphasis

    public init(
        id: Int,
        text: String,
        words: [Word],
        sectionIndex: Int,
        sentenceIndex: Int,
        isSentenceStart: Bool,
        isSentenceEnd: Bool,
        pauseAfter: PauseKind,
        emphasis: Emphasis
    ) {
        self.id = id
        self.text = text
        self.words = words
        self.sectionIndex = sectionIndex
        self.sentenceIndex = sentenceIndex
        self.isSentenceStart = isSentenceStart
        self.isSentenceEnd = isSentenceEnd
        self.pauseAfter = pauseAfter
        self.emphasis = emphasis
    }

    /// Lower-cased, punctuation-stripped tokens for speech matching.
    public var normalizedWords: [String] { words.map(\.normalized) }
}

public struct Word: Sendable, Equatable {
    /// The word as written, including any attached punctuation.
    public let text: String
    /// The word as it would be matched against recognised speech.
    public let normalized: String

    public init(text: String, normalized: String) {
        self.text = text
        self.normalized = normalized
    }
}

/// The pause a speaker would naturally take after a phrase. These are guidance, never
/// hard timing: the presentation layer scales them by delivery style and treats them as
/// suggestions the speaker may honour or ignore.
public enum PauseKind: String, Sendable, Codable, CaseIterable, Comparable {
    /// Mid-clause break; no real pause.
    case none
    /// Comma. A tiny beat.
    case beat
    /// Semicolon, colon, dash, parenthetical. A rhetorical beat.
    case clause
    /// End of sentence.
    case sentence
    /// Before or after a short, standalone statement that deserves room.
    case emphatic
    /// End of paragraph.
    case paragraph

    private var rank: Int {
        switch self {
        case .none: 0
        case .beat: 1
        case .clause: 2
        case .sentence: 3
        case .emphatic: 4
        case .paragraph: 5
        }
    }

    public static func < (lhs: PauseKind, rhs: PauseKind) -> Bool { lhs.rank < rhs.rank }
}

public enum Emphasis: String, Sendable, Codable {
    case normal
    /// A phrase that carries the point: a short standalone sentence, an exclamation, a
    /// deliberately isolated line. Rendered with a touch more weight and given room around it.
    case strong
}
