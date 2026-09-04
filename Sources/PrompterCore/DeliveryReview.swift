import Foundation

/// A restrained read on how a session went. Everything here is computed from what we can
/// actually measure (phrase timings and, with Voice Follow, when words were heard). Where
/// the data is thin, the review says so rather than inventing precision.
public struct DeliveryReview: Sendable, Equatable {
    public struct SectionPace: Sendable, Equatable {
        public let sectionIndex: Int
        public let wordsPerMinute: Double
    }

    public struct PauseCheck: Sendable, Equatable {
        public let phraseIndex: Int
        public let suggested: TimeInterval
        public let observed: TimeInterval
        public var wasTaken: Bool { observed >= suggested * 0.6 }
    }

    /// False when the session was too short to say anything useful.
    public let hasEnoughData: Bool
    /// 0…1 share of the script the speaker reached.
    public let completion: Double
    public let activeDuration: TimeInterval
    public let averageWordsPerMinute: Double?
    /// Target speaking rate for the chosen style, including its pauses.
    public let targetWordsPerMinute: Double
    public let sectionPaces: [SectionPace]
    /// Section noticeably quicker than the rest, if any.
    public let rushedSection: Int?
    public let pauseChecks: [PauseCheck]
    /// Hesitations: gaps well beyond any suggested pause.
    public let longPauses: [PauseCheck]
    /// 0…10, one decimal.
    public let score: Double
    public let headline: String
    public let notes: [String]

    public var pausesSuggested: Int { pauseChecks.count }
    public var pausesTaken: Int { pauseChecks.filter(\.wasTaken).count }
    public var skippedPauses: [PauseCheck] { pauseChecks.filter { !$0.wasTaken } }

    public init(log: DeliveryLog, script: PresentationScript, plan: PacePlan, styleName: String? = nil) {
        let phrases = script.phrases
        let visits = log.visits.filter { $0.duration != nil && phrases.indices.contains($0.phraseIndex) }
        let active = log.activeDuration ?? 0
        activeDuration = active

        let furthest = log.furthestPhrase ?? -1
        completion = phrases.isEmpty ? 0 : Double(furthest + 1) / Double(phrases.count)

        // Target pace: the plan's own words-per-minute once its pauses are included.
        let planWords = Double(script.wordCount)
        targetWordsPerMinute = plan.totalDuration > 0 ? planWords / (plan.totalDuration / 60) : plan.profile.wordsPerMinute

        // Not enough to go on: bail out honestly.
        let spokenWords = visits.reduce(0.0) { $0 + Double(phrases[$1.phraseIndex].words.count) }
        guard active >= 8, visits.count >= 3, spokenWords >= 20 else {
            hasEnoughData = false
            averageWordsPerMinute = nil
            sectionPaces = []
            rushedSection = nil
            pauseChecks = []
            longPauses = []
            score = 0
            headline = "Too short to review"
            notes = ["Run through at least a few sentences and Prompter will tell you how it went."]
            return
        }

        hasEnoughData = true

        // Overall pace. Words per minute the way a speech coach means it: pauses included.
        let avg = spokenWords / (active / 60)
        averageWordsPerMinute = avg

        // Per-section pace, from the time spent in each section's phrases.
        var sectionWords: [Int: Double] = [:]
        var sectionTime: [Int: TimeInterval] = [:]
        for v in visits {
            let s = phrases[v.phraseIndex].sectionIndex
            sectionWords[s, default: 0] += Double(phrases[v.phraseIndex].words.count)
            sectionTime[s, default: 0] += v.duration ?? 0
        }
        let paces = sectionWords.keys.sorted().compactMap { s -> SectionPace? in
            guard let t = sectionTime[s], t >= 4, let w = sectionWords[s], w >= 12 else { return nil }
            return SectionPace(sectionIndex: s, wordsPerMinute: w / (t / 60))
        }
        sectionPaces = paces
        if paces.count >= 2, let fastest = paces.max(by: { $0.wordsPerMinute < $1.wordsPerMinute }),
           fastest.wordsPerMinute > avg * 1.18, fastest.wordsPerMinute > targetWordsPerMinute * 1.12 {
            rushedSection = fastest.sectionIndex
        } else {
            rushedSection = nil
        }

        // Pauses. Only measurable when Voice Follow heard words on both sides of a boundary.
        var checks: [PauseCheck] = []
        var hesitations: [PauseCheck] = []
        for (a, b) in zip(visits, visits.dropFirst()) where b.phraseIndex == a.phraseIndex + 1 {
            guard let heardLast = a.lastSpeechAt, let heardFirst = b.firstSpeechAt else { continue }
            let phrase = phrases[a.phraseIndex]
            let suggested = plan.timing(at: a.phraseIndex)?.pause ?? 0
            let observed = max(0, heardFirst - heardLast)
            if phrase.pauseAfter >= .sentence, suggested > 0 {
                checks.append(PauseCheck(phraseIndex: a.phraseIndex, suggested: suggested, observed: observed))
            }
            if observed > max(4.0, suggested * 3) {
                hesitations.append(PauseCheck(phraseIndex: a.phraseIndex, suggested: suggested, observed: observed))
            }
        }
        pauseChecks = checks
        longPauses = hesitations

        // Score: start from 10 and take off for the things a coach would mention.
        var penalty = 0.0
        let paceRatio = avg / targetWordsPerMinute
        if paceRatio > 1.25 || paceRatio < 0.75 { penalty += 2.0 }
        else if paceRatio > 1.12 || paceRatio < 0.85 { penalty += 1.0 }
        if rushedSection != nil { penalty += 1.0 }
        let skipped = checks.filter { !$0.wasTaken }
        if !checks.isEmpty {
            let skippedShare = Double(skipped.count) / Double(checks.count)
            penalty += min(2.0, skippedShare * 3.0)
        }
        if hesitations.count >= 3 { penalty += 0.5 }
        if completion < 0.9 { penalty += (0.9 - completion) * 3 }
        score = (max(0, 10 - penalty) * 10).rounded() / 10

        // Words.
        var lines: [String] = []
        let headlineText: String
        switch paceRatio {
        case ..<0.85: headlineText = "A little slow overall."
        case 0.85..<1.12: headlineText = rushedSection == nil ? "Strong overall pace." : "Good pace, with one quick stretch."
        case 1.12..<1.25: headlineText = "A little quick overall."
        default: headlineText = "Noticeably quick overall."
        }
        headline = headlineText

        let styleLabel = styleName.map { "a \($0) delivery" } ?? "your chosen pace"
        lines.append("You averaged \(Int(avg.rounded())) words per minute; \(styleLabel) of this script lands around \(Int(targetWordsPerMinute.rounded())).")
        if let r = rushedSection, let pace = paces.first(where: { $0.sectionIndex == r }) {
            let opener = phrases.first { $0.sectionIndex == r }?.text ?? ""
            lines.append("You sped up to \(Int(pace.wordsPerMinute.rounded())) around “\(Self.shorten(opener))”.")
        }
        if !checks.isEmpty {
            lines.append("\(checks.filter(\.wasTaken).count) of \(checks.count) suggested pauses were taken.")
            // The most important skipped pause gets a specific, actionable line.
            if let miss = skipped.max(by: { phrases[$0.phraseIndex].pauseAfter < phrases[$1.phraseIndex].pauseAfter }) {
                let text = phrases[miss.phraseIndex].text
                lines.append("Try giving “\(Self.shorten(text))” another half-second before continuing.")
            }
        }
        if hesitations.count >= 3 {
            lines.append("There were \(hesitations.count) long gaps. If those weren't deliberate, a glance at the next line before you finish the current one helps.")
        }
        if completion < 0.95 {
            lines.append("You covered \(Int((completion * 100).rounded()))% of the script.")
        }
        notes = lines
    }

    /// Quote-ready: trailing punctuation dropped, cut at a word boundary if long.
    private static func shorten(_ text: String, max: Int = 56) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = t.last, last.isPunctuation { t.removeLast() }
        guard t.count > max else { return t }
        let words = t.split(separator: " ")
        var out = ""
        for w in words {
            if out.count + w.count + 1 > max - 1 { break }
            out += (out.isEmpty ? "" : " ") + w
        }
        return (out.isEmpty ? String(t.prefix(max - 1)) : out) + "…"
    }
}
