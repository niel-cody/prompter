import Foundation

/// What kind of thing was said. These are the headings the Markdown export groups under,
/// so they double as the categories a product person sorts feedback into afterwards.
public enum CaptureCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case feedback
    case insight
    case sentiment
    case question
    case objection
    case decision
    case action
    case quote

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .feedback: "Feedback"
        case .insight: "Insight"
        case .sentiment: "Sentiment"
        case .question: "Question"
        case .objection: "Objection"
        case .decision: "Decision"
        case .action: "Action"
        case .quote: "Quote"
        }
    }

    /// Plural heading used in the Markdown export.
    public var heading: String {
        switch self {
        case .feedback: "Feedback"
        case .insight: "Insights"
        case .sentiment: "Sentiment"
        case .question: "Questions"
        case .objection: "Objections"
        case .decision: "Decisions"
        case .action: "Actions"
        case .quote: "Quotes"
        }
    }

    /// SF Symbol name. Kept as a string so this module stays free of AppKit.
    public var symbolName: String {
        switch self {
        case .feedback: "bubble.left"
        case .insight: "lightbulb"
        case .sentiment: "face.smiling"
        case .question: "questionmark.circle"
        case .objection: "hand.raised"
        case .decision: "checkmark.seal"
        case .action: "arrow.right.circle"
        case .quote: "quote.opening"
        }
    }
}

public enum Sentiment: String, Codable, CaseIterable, Sendable {
    case positive, neutral, negative, mixed

    public var displayName: String { rawValue.capitalized }
}

/// One thing worth keeping from a session: a piece of feedback, a question, a decision.
/// Detected ones start as suggestions (`isKept == false`) until the user keeps them.
public struct Capture: Codable, Sendable, Equatable, Identifiable {
    public enum Source: String, Codable, Sendable {
        /// Flagged by `InsightDetector` from the transcript.
        case detected
        /// The user pressed Mark Insight; the text is the last stretch of transcript.
        case marked
        /// Typed by the user.
        case typed
    }

    public var id: UUID
    public var category: CaptureCategory
    public var text: String
    /// Seconds from the start of the session.
    public var at: TimeInterval
    public var sentiment: Sentiment
    public var source: Source
    public var isKept: Bool
    public var tags: [String]
    /// Who said it, as labelled on the transcript ("Me", "Them", or a name). Nil for typed notes.
    public var speaker: String?

    public init(id: UUID = UUID(), category: CaptureCategory, text: String, at: TimeInterval,
                sentiment: Sentiment = .neutral, source: Source = .typed, isKept: Bool = true, tags: [String] = [],
                speaker: String? = nil) {
        self.id = id
        self.category = category
        self.text = text
        self.at = at
        self.sentiment = sentiment
        self.source = source
        self.isKept = isKept
        self.tags = tags
        self.speaker = speaker
    }

    private enum CodingKeys: String, CodingKey { case id, category, text, at, sentiment, source, isKept, tags, speaker }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        category = try c.decode(CaptureCategory.self, forKey: .category)
        text = try c.decode(String.self, forKey: .text)
        at = try c.decode(TimeInterval.self, forKey: .at)
        sentiment = try c.decodeIfPresent(Sentiment.self, forKey: .sentiment) ?? .neutral
        source = try c.decodeIfPresent(Source.self, forKey: .source) ?? .typed
        isKept = try c.decodeIfPresent(Bool.self, forKey: .isKept) ?? true
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
    }
}

/// Which audio stream a piece of transcript came from. On a call this is what separates
/// the person at the Mac from everyone else: the microphone is "Me", system audio is "Them".
public enum AudioChannel: String, Codable, Sendable, CaseIterable {
    case microphone
    case system
}

/// A settled piece of transcript with the audio time it covers, which channel it came
/// from, and who the note thinks said it.
public struct TranscriptSegment: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String
    public var channel: AudioChannel
    /// A name or label. Nil means the channel's default ("Me", "Them", or "Room").
    public var speaker: String?
    /// True while the label is a guess from context; false once the user set or accepted it.
    public var speakerIsSuggested: Bool

    public init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String,
                channel: AudioChannel = .microphone, speaker: String? = nil, speakerIsSuggested: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.channel = channel
        self.speaker = speaker
        self.speakerIsSuggested = speakerIsSuggested
    }

    private enum CodingKeys: String, CodingKey { case id, start, end, text, channel, speaker, speakerIsSuggested }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(TimeInterval.self, forKey: .start)
        end = try c.decode(TimeInterval.self, forKey: .end)
        text = try c.decode(String.self, forKey: .text)
        channel = try c.decodeIfPresent(AudioChannel.self, forKey: .channel) ?? .microphone
        speaker = try c.decodeIfPresent(String.self, forKey: .speaker)
        speakerIsSuggested = try c.decodeIfPresent(Bool.self, forKey: .speakerIsSuggested) ?? false
    }
}

/// A prompt the template asks and the user's answer, used before (prep) and after (wrap-up).
public struct TemplateField: Codable, Sendable, Equatable, Identifiable {
    public var prompt: String
    public var answer: String
    public var id: String { prompt }

    public init(prompt: String, answer: String = "") {
        self.prompt = prompt
        self.answer = answer
    }
}

/// A meeting template: what to think about beforehand, what to write up afterwards.
public struct MeetingTemplate: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var prepPrompts: [String]
    public var wrapUpSections: [String]
    public var tags: [String]

    public init(id: String, name: String, summary: String, prepPrompts: [String], wrapUpSections: [String], tags: [String] = []) {
        self.id = id
        self.name = name
        self.summary = summary
        self.prepPrompts = prepPrompts
        self.wrapUpSections = wrapUpSections
        self.tags = tags
    }

    public static let pitchFeedback = MeetingTemplate(
        id: "pitch-feedback",
        name: "Pitch feedback",
        summary: "You present an idea; the room reacts. Captures what landed, what didn't, and what they asked.",
        prepPrompts: [
            "What am I pitching, in one sentence?",
            "What decision or reaction do I want from this room?",
            "What's the strongest objection I expect?",
        ],
        wrapUpSections: ["What landed", "What didn't", "Open questions", "Next steps"],
        tags: ["pitch"]
    )

    public static let customerDiscovery = MeetingTemplate(
        id: "customer-discovery",
        name: "Customer discovery",
        summary: "A conversation with a customer or user about their problem. Captures pains, workarounds and quotes.",
        prepPrompts: [
            "Who am I talking to and what's their role?",
            "What hypothesis am I testing?",
            "Three questions I must ask",
        ],
        wrapUpSections: ["Their problem in their words", "Current workaround", "What surprised me", "Follow-ups"],
        tags: ["discovery", "customer"]
    )

    public static let stakeholderReview = MeetingTemplate(
        id: "stakeholder-review",
        name: "Stakeholder review",
        summary: "A roadmap, PRD or design review with leadership or peers. Captures decisions, objections and asks.",
        prepPrompts: [
            "What am I asking this group to decide?",
            "Who needs to be convinced, and of what?",
            "What's the fallback if the answer is no?",
        ],
        wrapUpSections: ["Decisions", "Concerns raised", "Commitments", "Follow-ups"],
        tags: ["review", "stakeholders"]
    )

    public static let blank = MeetingTemplate(
        id: "blank",
        name: "Blank",
        summary: "Just notes, transcript and captures.",
        prepPrompts: [],
        wrapUpSections: ["Summary", "Next steps"]
    )

    public static let builtIn: [MeetingTemplate] = [pitchFeedback, customerDiscovery, stakeholderReview, blank]

    public static func builtIn(id: String) -> MeetingTemplate? {
        builtIn.first { $0.id == id }
    }
}

/// One session's notes: the user's own notes, the transcript, the captures, the template's
/// prep and wrap-up. Persisted as JSON and mirrored to Markdown by `MeetingStore`.
public struct MeetingNote: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var templateID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var startedAt: Date?
    public var endedAt: Date?
    /// Free text: who was in the room.
    public var attendees: String
    /// The script being pitched, if this session goes with one from the library.
    public var scriptID: UUID?
    public var prep: [TemplateField]
    /// The user's own notes, typed during the meeting. Markdown.
    public var notes: String
    public var wrapUp: [TemplateField]
    public var transcript: [TranscriptSegment]
    public var captures: [Capture]
    public var tags: [String]
    /// Everyone is in the room with the Mac, so the microphone hears all of them and there is
    /// no system audio to tap. On a call (the default) the mic is you and system audio is them.
    public var isInPerson: Bool

    public static let meLabel = "Me"
    public static let themLabel = "Them"
    public static let roomLabel = "Room"

    public init(id: UUID = UUID(), title: String, template: MeetingTemplate = .pitchFeedback, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.templateID = template.id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.attendees = ""
        self.prep = template.prepPrompts.map { TemplateField(prompt: $0) }
        self.notes = ""
        self.wrapUp = template.wrapUpSections.map { TemplateField(prompt: $0) }
        self.transcript = []
        self.captures = []
        self.tags = template.tags
        self.isInPerson = false
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, templateID, createdAt, updatedAt, startedAt, endedAt, attendees, scriptID, prep, notes, wrapUp,
             transcript, captures, tags, isInPerson
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        templateID = try c.decode(String.self, forKey: .templateID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        attendees = try c.decodeIfPresent(String.self, forKey: .attendees) ?? ""
        scriptID = try c.decodeIfPresent(UUID.self, forKey: .scriptID)
        prep = try c.decodeIfPresent([TemplateField].self, forKey: .prep) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        wrapUp = try c.decodeIfPresent([TemplateField].self, forKey: .wrapUp) ?? []
        transcript = try c.decodeIfPresent([TranscriptSegment].self, forKey: .transcript) ?? []
        captures = try c.decodeIfPresent([Capture].self, forKey: .captures) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        isInPerson = try c.decodeIfPresent(Bool.self, forKey: .isInPerson) ?? false
    }

    public var template: MeetingTemplate? { MeetingTemplate.builtIn(id: templateID) }

    // MARK: - Speakers

    /// The label a channel gets when nobody has been named.
    public func defaultSpeaker(for channel: AudioChannel) -> String {
        switch channel {
        case .microphone: isInPerson ? Self.roomLabel : Self.meLabel
        case .system: Self.themLabel
        }
    }

    public func speakerLabel(of segment: TranscriptSegment) -> String {
        segment.speaker ?? defaultSpeaker(for: segment.channel)
    }

    /// Every label in use, in order of first appearance.
    public var speakers: [String] {
        var seen = Set<String>()
        return transcript.map(speakerLabel(of:)).filter { seen.insert($0).inserted }
    }

    /// Names typed into the attendees field, one per comma or line.
    public var attendeeNames: [String] {
        attendees.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline || $0 == "&" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Set the speaker of one line. Passing the channel default clears any name.
    public mutating func setSpeaker(_ label: String, for segmentID: UUID) {
        guard let i = transcript.firstIndex(where: { $0.id == segmentID }) else { return }
        let cleaned = label.trimmingCharacters(in: .whitespaces)
        transcript[i].speaker = cleaned.isEmpty || cleaned == defaultSpeaker(for: transcript[i].channel) ? nil : cleaned
        transcript[i].speakerIsSuggested = false
        relabelCaptures(overlapping: transcript[i])
    }

    /// Rename every line (and capture) currently labelled `old`, confirmed or suggested.
    public mutating func relabel(_ old: String, to new: String) {
        let cleaned = new.trimmingCharacters(in: .whitespaces)
        for i in transcript.indices where speakerLabel(of: transcript[i]) == old {
            transcript[i].speaker = cleaned.isEmpty || cleaned == defaultSpeaker(for: transcript[i].channel) ? nil : cleaned
            transcript[i].speakerIsSuggested = false
        }
        for i in captures.indices where captures[i].speaker == old {
            captures[i].speaker = cleaned.isEmpty ? nil : cleaned
        }
    }

    /// Accept a suggested name as correct for every line that carries it.
    public mutating func confirmSpeaker(_ label: String) {
        for i in transcript.indices where transcript[i].speaker == label { transcript[i].speakerIsSuggested = false }
    }

    private mutating func relabelCaptures(overlapping segment: TranscriptSegment) {
        let label = speakerLabel(of: segment)
        for i in captures.indices where captures[i].source == .detected && captures[i].at >= segment.start - 0.5 && captures[i].at <= segment.end + 0.5 {
            captures[i].speaker = label
        }
    }

    public var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (endedAt ?? Date()).timeIntervalSince(startedAt)
    }

    public var isEnded: Bool { endedAt != nil }

    public var keptCaptures: [Capture] { captures.filter(\.isKept).sorted { $0.at < $1.at } }
    public var suggestedCaptures: [Capture] { captures.filter { !$0.isKept }.sorted { $0.at < $1.at } }

    public func captures(in category: CaptureCategory) -> [Capture] {
        keptCaptures.filter { $0.category == category }
    }

    /// The whole transcript as one string.
    public var transcriptText: String {
        transcript.map(\.text).joined(separator: " ")
    }

    /// Transcript spoken in the last `window` seconds before `time`. What Mark Insight grabs.
    public func recentTranscript(before time: TimeInterval, window: TimeInterval) -> String {
        transcript.filter { $0.end >= time - window && $0.start <= time }
            .map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The room's overall mood, from kept captures that carry a sentiment.
    public var overallSentiment: Sentiment {
        let kept = keptCaptures.map(\.sentiment).filter { $0 != .neutral }
        guard !kept.isEmpty else { return .neutral }
        let positive = kept.filter { $0 == .positive }.count
        let negative = kept.filter { $0 == .negative }.count
        if positive > negative * 2 { return .positive }
        if negative > positive * 2 { return .negative }
        return .mixed
    }

    /// Counts by category, kept captures only.
    public var categoryCounts: [CaptureCategory: Int] {
        Dictionary(grouping: keptCaptures, by: \.category).mapValues(\.count)
    }
}
