import Foundation

/// Finds where in the script the speaker is, from the words they have just said.
///
/// The matcher keeps an anchor (the last confirmed script word) and aligns the most recent
/// spoken words against a window of script words around it. It moves when the alignment is
/// convincing, holds when the speaker improvises, follows them forward when they skip, and
/// back when they restart an earlier line. It never guesses on thin evidence: a wrong jump
/// is far worse for the speaker than a moment's delay.
public struct ScriptMatcher: Sendable {
    public struct Config: Sendable {
        /// How far back from the anchor we look (in script words).
        public var windowBack = 40
        /// How far ahead of the anchor we look (in script words).
        public var windowAhead = 160
        /// How many recent spoken words are aligned each update.
        public var tailLength = 12
        /// Minimum alignment score to move to a nearby position.
        public var minScoreNear = 2.4
        /// Minimum alignment score to jump far ahead / back once we have an anchor.
        public var minScoreFar = 4.0
        /// Minimum score to anchor when we have no position yet (or have lost it). With nothing
        /// to protect, a plausible match beats an empty prompt.
        public var minScoreColdStart = 3.0
        /// Positions within this many script words of the anchor count as "near".
        public var nearRange = 30
        /// After this many unmatched updates we widen the search to the whole script.
        public var lostAfterUpdates = 6

        public init() {}
    }

    public struct Result: Sendable, Equatable {
        public let phraseIndex: Int
        /// Index into the script's flattened word list of the last matched word.
        public let wordIndex: Int
        public let score: Double
        /// True when the speaker has said the last word of the phrase.
        public let atPhraseEnd: Bool
    }

    public let config: Config
    private let words: [String]
    private let wordToPhrase: [Int]
    private let phraseFirstWord: [Int]
    private let phraseLastWord: [Int]

    /// Last confirmed script word index, or -1 before anything has matched.
    public private(set) var anchor: Int = -1
    private var unmatchedUpdates = 0

    public init(script: PresentationScript, config: Config = Config()) {
        self.config = config
        var words: [String] = []
        var map: [Int] = []
        var firsts: [Int] = []
        var lasts: [Int] = []
        for phrase in script.phrases {
            firsts.append(words.count)
            for word in phrase.normalizedWords {
                words.append(word)
                map.append(phrase.id)
            }
            lasts.append(words.count - 1)
        }
        self.words = words
        self.wordToPhrase = map
        self.phraseFirstWord = firsts
        self.phraseLastWord = lasts
    }

    public var currentPhrase: Int? { anchor >= 0 && anchor < wordToPhrase.count ? wordToPhrase[anchor] : nil }

    /// Re-anchor after the user moves manually: matching resumes from the start of `phrase`.
    public mutating func reset(toPhrase phrase: Int) {
        guard phraseFirstWord.indices.contains(phrase) else { anchor = -1; return }
        anchor = phraseFirstWord[phrase] - 1
        unmatchedUpdates = 0
    }

    /// Feed the latest transcript (already normalised into tokens). Returns a result only
    /// when the matcher is confident enough to (re)position the prompt.
    public mutating func update(spoken tokens: [String]) -> Result? {
        guard !words.isEmpty, !tokens.isEmpty else { return nil }
        let tail = Array(tokens.suffix(config.tailLength))

        let lost = anchor < 0 || unmatchedUpdates >= config.lostAfterUpdates
        let lo = lost ? 0 : max(0, anchor - config.windowBack)
        let hi = lost ? words.count : min(words.count, anchor + config.windowAhead + 1)

        guard let best = align(tail, windowRange: lo..<hi) else {
            unmatchedUpdates += 1
            return nil
        }

        let distance = anchor < 0 ? Int.max : abs(best.end - anchor)
        let isNear = distance <= config.nearRange
        let threshold = lost ? config.minScoreColdStart : (isNear ? config.minScoreNear : config.minScoreFar)
        guard best.score >= threshold else {
            unmatchedUpdates += 1
            return nil
        }

        // Moving backwards is only ever a deliberate restart; ask for a little more.
        if anchor >= 0, best.end < anchor - 2, best.score < config.minScoreNear + 1.0 {
            unmatchedUpdates += 1
            return nil
        }

        anchor = best.end
        unmatchedUpdates = 0
        let phrase = wordToPhrase[best.end]
        return Result(phraseIndex: phrase, wordIndex: best.end, score: best.score,
                      atPhraseEnd: best.end == phraseLastWord[phrase])
    }

    // MARK: - Alignment

    private struct Alignment { var score: Double; var end: Int }

    /// Smith–Waterman local alignment of the spoken tail against the script window. We only
    /// need the best end position in the script and its score, not the full path.
    private func align(_ spoken: [String], windowRange: Range<Int>) -> Alignment? {
        let m = spoken.count
        let n = windowRange.count
        guard m > 0, n > 0 else { return nil }
        let base = windowRange.lowerBound

        var prev = [Double](repeating: 0, count: n + 1)
        var curr = [Double](repeating: 0, count: n + 1)
        var best = Alignment(score: 0, end: -1)

        for i in 1...m {
            let s = spoken[i - 1]
            let isFiller = TextNormalizer.fillerWords.contains(s)
            let skipSpokenPenalty = isFiller ? 0.1 : 0.35
            curr[0] = 0
            for j in 1...n {
                let w = words[base + j - 1]
                let sub = prev[j - 1] + Self.similarity(spoken: s, script: w)
                let skipScript = curr[j - 1] - 0.45
                let skipSpoken = prev[j] - skipSpokenPenalty
                let v = max(0, sub, skipScript, skipSpoken)
                curr[j] = v
                if v > best.score + 1e-9 {
                    best = Alignment(score: v, end: base + j - 1)
                } else if abs(v - best.score) <= 1e-9, best.end >= 0, anchor >= 0,
                          abs(base + j - 1 - anchor) < abs(best.end - anchor) {
                    // Tie: prefer the position closest to where we already are.
                    best.end = base + j - 1
                }
            }
            swap(&prev, &curr)
        }
        return best.end >= 0 ? best : nil
    }

    /// How well a spoken token matches a script token. Content words are worth more than
    /// stop words; near-misses (ASR slips, plurals) earn partial credit.
    static func similarity(spoken: String, script: String) -> Double {
        if spoken == script {
            return TextNormalizer.stopWords.contains(script) ? 0.5 : 1.0
        }
        guard script.count >= 4, spoken.count >= 3 else { return -0.6 }
        if spoken.hasPrefix(script) || script.hasPrefix(spoken) {
            let shorter = min(spoken.count, script.count)
            return shorter >= 4 ? 0.8 : -0.3
        }
        let d = editDistance(spoken, script)
        if d == 1 { return 0.8 }
        if d == 2, script.count >= 6 { return 0.5 }
        return -0.6
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a.utf8), b = Array(b.utf8)
        if abs(a.count - b.count) > 2 { return 3 }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(1, a.count) where i <= a.count {
            curr[0] = i
            for j in 1...max(1, b.count) where j <= b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
