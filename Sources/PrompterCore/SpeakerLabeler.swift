import Foundation

/// Guesses who said a transcript line. The channel already separates the person at the Mac
/// from everyone else; this tries to put names on the "everyone else" side using what people
/// say to and about each other, and marks every guess as a suggestion for the user to fix.
///
/// Three cues, in order of trust:
/// 1. Introductions in the line itself: "this is Priya", "Priya here", "I'm Priya".
/// 2. Being addressed just before: the mic says "Priya, what do you think?" and the next
///    remote line is probably Priya.
/// 3. Continuity: a remote line that follows another within a short gap is probably the
///    same person still talking.
///
/// Names are only trusted when they look like names and, for addressing, are already known
/// (from the attendees field or an earlier introduction). Apple's recogniser has no speaker
/// diarization, so two remote voices with no cues both stay "Them".
public struct SpeakerLabeler: Sendable {
    public struct Suggestion: Equatable, Sendable {
        public let speaker: String
        public let cue: String
    }

    /// How long after being addressed a reply is still attributed to the person named.
    public var addressWindow: TimeInterval = 20
    /// A remote line this soon after the previous one is assumed to be the same speaker.
    public var continuityGap: TimeInterval = 3

    public init() {}

    private static let introPatterns: [NSRegularExpression] = [
        // Cues are case-insensitive; the captured name must still be capitalised.
        #"(?i:^|[,.!?]\s*|\bhi\s+|\bhello\s+|\bhey\s+|\bokay\s+|\bok\s+|\bso\s+)(?i:this is|it's|it is|i'm|i am|my name is|my name's)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)\b"#,
        #"(?i:^|[,.!?]\s*|\bhi\s+|\bhello\s+|\bhey\s+)([A-Z][a-z]+) (?i:here)\b"#,
        #"\b(?i:you've got|you have|it's just)\s+([A-Z][a-z]+)\b(?i: here| speaking)"#,
    ].map { try! NSRegularExpression(pattern: $0, options: []) }

    /// Words that are capitalised at the start of a sentence but are not names.
    private static let notNames: Set<String> = [
        "i", "the", "this", "that", "these", "those", "it", "its", "okay", "ok", "yes", "no", "hi", "hello",
        "hey", "so", "and", "but", "well", "right", "thanks", "thank", "great", "good", "fine", "sure", "what",
        "why", "how", "when", "where", "who", "which", "just", "really", "all", "very", "here", "there", "now",
        "me", "them", "room", "we", "you", "they", "he", "she", "one", "two", "three", "first", "next", "last",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february",
        "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "zoom", "teams", "google", "slack", "apple", "mac", "iphone",
    ]

    static func looksLikeName(_ s: String) -> Bool {
        let parts = s.split(separator: " ")
        guard !parts.isEmpty, parts.count <= 2 else { return false }
        return parts.allSatisfy { part in
            part.count >= 2 && part.first!.isUppercase && part.dropFirst().allSatisfy(\.isLowercase)
                && !notNames.contains(part.lowercased())
        }
    }

    /// A name the speaker gives for themself in this line, if any.
    public static func introducedName(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in introPatterns {
            guard let m = pattern.firstMatch(in: text, options: [], range: range), m.numberOfRanges > 1,
                  let r = Range(m.range(at: 1), in: text) else { continue }
            let name = String(text[r])
            if looksLikeName(name) { return name }
        }
        return nil
    }

    /// A known name this line addresses ("Priya, what do you think?", "over to you, Sam").
    public static func addressedName(in text: String, known: [String]) -> String? {
        guard !known.isEmpty else { return nil }
        let lowered = text.lowercased()
        // Longest names first so "Sam Lee" beats "Sam".
        for name in known.sorted(by: { $0.count > $1.count }) {
            let n = name.lowercased()
            guard let r = lowered.range(of: n) else { continue }
            // Whole word.
            if let before = lowered[..<r.lowerBound].last, before.isLetter { continue }
            if let after = lowered[r.upperBound...].first, after.isLetter { continue }
            return name
        }
        return nil
    }

    /// Suggest a speaker for `segment`, given everything transcribed before it.
    public func suggest(for segment: TranscriptSegment, in note: MeetingNote) -> Suggestion? {
        let known = knownNames(in: note)

        if let name = Self.introducedName(in: segment.text) {
            return Suggestion(speaker: name, cue: "introduced")
        }
        // On a call the mic is one known person; only remote lines need naming.
        guard segment.channel == .system || note.isInPerson else { return nil }

        let earlier = note.transcript.filter { $0.id != segment.id && $0.start < segment.start }
        // Addressed by the other channel just before.
        if segment.channel == .system,
           let asker = earlier.last(where: { $0.channel == .microphone && segment.start - $0.end <= addressWindow }),
           let name = Self.addressedName(in: asker.text, known: known) {
            return Suggestion(speaker: name, cue: "addressed")
        }
        // Same person still talking.
        if let previous = earlier.last(where: { $0.channel == segment.channel }),
           let name = previous.speaker, segment.start - previous.end <= continuityGap {
            return Suggestion(speaker: name, cue: "continued")
        }
        return nil
    }

    /// Attendees plus anyone who has introduced themself or been named on a line.
    public func knownNames(in note: MeetingNote) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in note.attendeeNames + note.transcript.compactMap(\.speaker) where Self.looksLikeName(name) {
            if seen.insert(name.lowercased()).inserted { out.append(name) }
        }
        return out
    }
}
