import Foundation

/// Flags sentences in a transcript that a product person would want to keep: feedback,
/// objections, questions, decisions, actions, insights, and anything said with feeling.
///
/// Deliberately rule-based and on-device. It runs over every settled transcript segment as
/// it arrives, so it must be cheap, and it must never need a network. It is a first pass:
/// what it flags are suggestions the user keeps or dismisses, not conclusions.
public struct InsightDetector: Sendable {
    public struct Detection: Equatable, Sendable {
        public let category: CaptureCategory
        public let sentiment: Sentiment
        public let text: String
        /// Which cue fired, for the trace tool.
        public let cue: String
    }

    public init() {}

    // MARK: - Sentences

    /// Splits recognised text into sentences, keeping the terminator so questions survive.
    /// Text without punctuation (some recognisers emit none) is one sentence.
    public static func sentences(in text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "?" || ch == "!" {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    // MARK: - Sentiment

    private static let positiveWords: Set<String> = [
        "love", "like", "great", "good", "excellent", "helpful", "clear", "useful", "easy",
        "excited", "exciting", "valuable", "brilliant", "perfect", "nice", "works", "solves",
        "better", "promising", "agree", "yes", "awesome", "fantastic", "simple", "intuitive",
        "happy", "impressed", "strong", "compelling", "obvious", "sense", "fast", "elegant",
        "keen", "interested", "interesting", "win", "delighted",
    ]

    private static let negativeWords: Set<String> = [
        "hate", "dislike", "confusing", "confused", "hard", "difficult", "unclear", "slow",
        "expensive", "worried", "worry", "concern", "concerned", "concerns", "problem",
        "problems", "frustrating", "frustrated", "annoying", "broken", "missing", "risk",
        "risky", "painful", "pain", "worse", "wrong", "doubt", "disagree", "blocker",
        "complicated", "clunky", "overwhelming", "awkward", "messy", "struggle", "struggling",
        "nervous", "unsure", "sceptical", "skeptical", "disappointed", "disappointing", "no",
        "waste", "bad", "terrible", "useless", "friction", "unhappy", "scary", "hesitant",
    ]

    private static let negators: Set<String> = ["not", "never", "no", "hardly", "without", "nobody", "nothing"]

    /// Lexicon sentiment with simple negation: a negator flips the next three words.
    public func sentiment(of text: String) -> Sentiment {
        let tokens = TextNormalizer.tokens(from: text)
        var positive = 0, negative = 0
        var flipRemaining = 0
        for token in tokens {
            if Self.negators.contains(token) {
                // "no" on its own is a negative word; "no problem" is a negated negative.
                flipRemaining = 3
                continue
            }
            let flip = flipRemaining > 0
            if flipRemaining > 0 { flipRemaining -= 1 }
            if Self.positiveWords.contains(token) {
                if flip { negative += 1 } else { positive += 1 }
            } else if Self.negativeWords.contains(token) {
                if flip { positive += 1 } else { negative += 1 }
            }
        }
        if positive == 0 && negative == 0 { return .neutral }
        if positive > 0 && negative > 0 && abs(positive - negative) <= 1 { return .mixed }
        return positive > negative ? .positive : .negative
    }

    /// How strongly the sentence leans either way, for the "said with feeling" catch-all.
    private func sentimentStrength(of text: String) -> Int {
        let tokens = TextNormalizer.tokens(from: text)
        return tokens.filter { Self.positiveWords.contains($0) || Self.negativeWords.contains($0) }.count
    }

    // MARK: - Cues

    /// Cue phrases are matched on normalised tokens, so "let's" matches "let us" and "won't
    /// work" matches "will not work". Order matters: the first category with a hit wins.
    private static let cues: [(CaptureCategory, [String])] = [
        (.decision, [
            "let us go with", "we will go with", "we agreed", "agreed", "decided", "decision is",
            "going to go with", "let us do that", "sign off", "signed off", "approved", "go ahead with",
            "we will do that", "we will do this", "that is the plan", "settled", "green light",
        ]),
        (.action, [
            "i will send", "i will follow up", "i will share", "i will get back", "i will put together",
            "i will set up", "i will write", "i will circulate", "can you send", "could you send",
            "can you share", "could you share", "can you put", "follow up", "next step", "next steps",
            "action item", "by friday", "by monday", "by tuesday", "by wednesday", "by thursday",
            "by next week", "by end of", "end of week", "end of the week", "we will set up",
            "send me", "let me know", "we need to schedule", "let us schedule", "take that away",
            "take it away", "i will take that", "own that", "owns that",
        ]),
        (.objection, [
            "concern", "concerned", "worried", "worry", "worries", "not sure", "not convinced",
            "would not work", "will not work", "does not work", "did not work", "problem is",
            "issue is", "pushback", "push back", "blocker", "do not think", "does not solve",
            "too expensive", "too complex", "too complicated", "too slow", "hard to see",
            "hard to justify", "not comfortable", "hesitant", "sceptical", "skeptical", "risk is",
            "risky", "what about the", "does not scale", "will not scale", "not going to work",
            "do not buy", "does not convince", "not clear why", "unclear why", "struggle to see",
        ]),
        (.feedback, [
            "i think", "i feel", "i like", "i love", "i do not like", "i would prefer", "would be nice",
            "would be great", "would be good", "would be better", "it would help", "confusing",
            "i wish", "we need", "what i want", "what i would want", "nice to have", "must have",
            "my feedback", "feels", "makes sense", "does not make sense", "hard to", "easy to",
            "i would want", "we want", "i want", "i would expect", "i expected", "looks",
            "seems", "my take", "my view", "from my side", "from my perspective", "i would rather",
            "i would love", "prefer", "should be", "should not be", "too many", "too much",
        ]),
        (.insight, [
            "turns out", "in practice", "in reality", "what happens is", "what actually happens",
            "the reason", "root cause", "today we", "right now we", "currently", "every time",
            "most of the time", "the real problem", "the real issue", "what we actually",
            "our customers", "our users", "customers keep", "users keep", "the way we", "we end up",
            "we always", "we usually", "we tend to", "the biggest", "the main thing", "what matters",
            "the pattern", "we see", "we have seen", "we noticed", "i have noticed", "interesting",
        ]),
    ]

    private static let questionStarts: [[String]] = [
        ["what", "if"], ["how", "would"], ["how", "do"], ["how", "does"], ["how", "will"], ["why", "would"],
        ["why", "do"], ["why", "does"], ["why", "not"], ["have", "you", "considered"], ["have", "you", "thought"],
        ["did", "you", "think"], ["what", "happens", "when"], ["what", "happens", "if"], ["is", "there", "a"],
        ["could", "we"], ["can", "we"], ["would", "you"], ["could", "you"], ["do", "you"], ["does", "it"],
        ["what", "about"], ["who", "would"], ["who", "is"], ["when", "would"], ["when", "will"], ["where", "does"],
    ]

    /// Classify one sentence. `nil` means nothing worth flagging.
    public func detect(_ sentence: String) -> Detection? {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = TextNormalizer.tokens(from: text)
        guard tokens.count >= 4 else { return nil }
        let mood = sentiment(of: text)

        for (category, phrases) in Self.cues {
            if let hit = phrases.first(where: { Self.contains(tokens, phrase: $0) }) {
                return Detection(category: category, sentiment: mood, text: text, cue: hit)
            }
            // Questions outrank feedback and insight but not decisions, actions, objections.
            if category == .objection, let q = questionCue(text: text, tokens: tokens) {
                return Detection(category: .question, sentiment: mood, text: text, cue: q)
            }
        }
        // A "but" or "however" carrying negative feeling is an objection without saying so.
        if mood == .negative, tokens.contains("but") || tokens.contains("however") {
            return Detection(category: .objection, sentiment: mood, text: text, cue: "but + negative")
        }
        if mood != .neutral, sentimentStrength(of: text) >= 2 {
            return Detection(category: .sentiment, sentiment: mood, text: text, cue: "strong sentiment")
        }
        return nil
    }

    /// On a call, the microphone is the presenter. Their own opinions aren't the feedback
    /// being collected, so only what they commit to (decisions, actions) is flagged from that
    /// channel. In person, the mic hears everyone and everything counts.
    public func detect(_ sentence: String, from channel: AudioChannel, inPerson: Bool) -> Detection? {
        guard let d = detect(sentence) else { return nil }
        if channel == .microphone, !inPerson, d.category != .decision, d.category != .action { return nil }
        return d
    }

    /// Run over a block of transcript text; one detection per sentence at most.
    public func detect(in text: String) -> [Detection] {
        Self.sentences(in: text).compactMap(detect)
    }

    private func questionCue(text: String, tokens: [String]) -> String? {
        if text.hasSuffix("?") { return "?" }
        for start in Self.questionStarts where tokens.starts(with: start) {
            return start.joined(separator: " ")
        }
        return nil
    }

    private static func contains(_ tokens: [String], phrase: String) -> Bool {
        let needle = phrase.split(separator: " ").map(String.init)
        guard !needle.isEmpty, tokens.count >= needle.count else { return false }
        if needle.count == 1 { return tokens.contains(needle[0]) }
        for i in 0...(tokens.count - needle.count) where tokens[i] == needle[0] {
            if Array(tokens[i..<(i + needle.count)]) == needle { return true }
        }
        return false
    }
}
