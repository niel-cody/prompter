import Foundation

/// Seeds a template's wrap-up sections from the kept captures, so the write-up starts
/// from what was actually said rather than a blank box. The user edits from there.
public enum MeetingWrapUp {
    /// Which captures belong under a wrap-up heading. Matched on words in the heading, so
    /// custom templates get sensible defaults too.
    static func captures(for heading: String, in note: MeetingNote) -> [Capture] {
        let h = heading.lowercased()
        let kept = note.keptCaptures
        func has(_ words: String...) -> Bool { words.contains { h.contains($0) } }

        if has("landed", "liked", "worked", "positive") {
            return kept.filter { ($0.category == .feedback || $0.category == .sentiment || $0.category == .quote) && $0.sentiment == .positive }
        }
        if has("didn't", "did not", "concern", "objection", "pushback", "negative", "risk") {
            return kept.filter { $0.category == .objection || (($0.category == .feedback || $0.category == .sentiment) && $0.sentiment == .negative) }
        }
        if has("question") { return kept.filter { $0.category == .question } }
        if has("decision") { return kept.filter { $0.category == .decision } }
        if has("next step", "follow", "commitment", "action", "owner") { return kept.filter { $0.category == .action } }
        if has("their words", "quote", "said") { return kept.filter { $0.category == .quote } }
        if has("workaround", "surprise", "insight", "learned", "problem") { return kept.filter { $0.category == .insight || $0.category == .quote } }
        if has("summary", "overview") { return kept }
        return []
    }

    /// Fill empty wrap-up answers with bullet lists of the matching captures. Answers the
    /// user has already written are left alone unless `overwrite` is set.
    public static func draft(_ note: inout MeetingNote, overwrite: Bool = false) {
        for i in note.wrapUp.indices {
            let existing = note.wrapUp[i].answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard overwrite || existing.isEmpty else { continue }
            let items = captures(for: note.wrapUp[i].prompt, in: note)
            guard !items.isEmpty else { continue }
            note.wrapUp[i].answer = items.map { capture in
                let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return "- " + (capture.category == .quote ? "\"\(text)\"" : text) + " (\(MeetingMarkdown.clock(capture.at)))"
            }.joined(separator: "\n")
        }
    }
}
