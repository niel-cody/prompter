import Foundation

/// Renders a `MeetingNote` as a Markdown document with YAML front matter: the format the
/// notes are kept in for anything downstream (Obsidian, grep, a categorising script, a
/// model). Stable headings per category are the contract; keep them.
public enum MeetingMarkdown {
    public static func render(_ note: MeetingNote, now: Date = Date()) -> String {
        var out: [String] = []
        out.append(frontMatter(note))
        out.append("# \(note.title.isEmpty ? "Untitled meeting" : note.title)")
        out.append("")

        var meta: [String] = []
        if let template = note.template { meta.append("Template: \(template.name)") }
        if let startedAt = note.startedAt { meta.append("Started: \(Self.dateTime.string(from: startedAt))") }
        if let duration = note.duration, note.isEnded { meta.append("Duration: \(clock(duration))") }
        if !note.attendees.trimmingCharacters(in: .whitespaces).isEmpty { meta.append("With: \(note.attendees)") }
        if !meta.isEmpty {
            out.append(meta.joined(separator: "  \n"))
            out.append("")
        }

        let prep = note.prep.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !prep.isEmpty {
            out.append("## Prep")
            out.append("")
            for field in prep {
                out.append("**\(field.prompt)**  ")
                out.append(field.answer.trimmingCharacters(in: .whitespacesAndNewlines))
                out.append("")
            }
        }

        let notes = note.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            out.append("## Notes")
            out.append("")
            out.append(notes)
            out.append("")
        }

        let kept = note.keptCaptures
        if !kept.isEmpty {
            out.append("## Captures")
            out.append("")
            for category in CaptureCategory.allCases {
                let items = kept.filter { $0.category == category }
                guard !items.isEmpty else { continue }
                out.append("### \(category.heading)")
                out.append("")
                for capture in items { out.append(line(for: capture)) }
                out.append("")
            }
        }

        let suggested = note.suggestedCaptures
        if !suggested.isEmpty {
            out.append("## Suggested")
            out.append("")
            out.append("_Flagged automatically; not yet reviewed._")
            out.append("")
            for capture in suggested { out.append(line(for: capture, showCategory: true)) }
            out.append("")
        }

        let wrap = note.wrapUp.filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !wrap.isEmpty {
            out.append("## Wrap-up")
            out.append("")
            for field in wrap {
                out.append("### \(field.prompt)")
                out.append("")
                out.append(field.answer.trimmingCharacters(in: .whitespacesAndNewlines))
                out.append("")
            }
        }

        if !note.transcript.isEmpty {
            out.append("## Transcript")
            out.append("")
            var lastSpeaker: String?
            for segment in note.transcript {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let speaker = note.speakerLabel(of: segment)
                if speaker != lastSpeaker {
                    if lastSpeaker != nil { out.append("") }
                    out.append("**\(speaker)**\(segment.speakerIsSuggested ? " _(suggested)_" : "")  ")
                    lastSpeaker = speaker
                }
                out.append("`\(clock(segment.start))` \(text)  ")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// One capture as a list item: timestamp, sentiment when it has one, the text, tags.
    static func line(for capture: Capture, showCategory: Bool = false) -> String {
        var parts = ["- `\(clock(capture.at))`"]
        if showCategory { parts.append("**\(capture.category.displayName)**") }
        if capture.sentiment != .neutral { parts.append("_\(capture.sentiment.rawValue)_") }
        let text = capture.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        parts.append(capture.category == .quote ? "\"\(text)\"" : text)
        if let speaker = capture.speaker, !speaker.isEmpty { parts.append("— \(speaker)") }
        if !capture.tags.isEmpty { parts.append(capture.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: " ")
    }

    static func frontMatter(_ note: MeetingNote) -> String {
        var lines = ["---"]
        lines.append("title: \(yaml(note.title.isEmpty ? "Untitled meeting" : note.title))")
        lines.append("id: \(note.id.uuidString.lowercased())")
        lines.append("date: \(Self.iso.string(from: note.startedAt ?? note.createdAt))")
        lines.append("template: \(note.templateID)")
        if let duration = note.duration, note.isEnded {
            lines.append("duration_seconds: \(Int(duration.rounded()))")
        }
        if !note.attendees.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append("attendees: \(yaml(note.attendees))")
        }
        let tags = (note.tags + ["prompter"]).map { $0.lowercased() }
        lines.append("tags: [\(Array(Set(tags)).sorted().joined(separator: ", "))]")
        lines.append("mode: \(note.isInPerson ? "in-person" : "call")")
        let speakers = note.speakers
        if !speakers.isEmpty { lines.append("speakers: [\(speakers.map(yaml).joined(separator: ", "))]") }
        lines.append("sentiment: \(note.overallSentiment.rawValue)")
        lines.append("captures: \(note.keptCaptures.count)")
        let counts = note.categoryCounts
        if !counts.isEmpty {
            lines.append("categories:")
            for category in CaptureCategory.allCases {
                if let n = counts[category] { lines.append("  \(category.rawValue): \(n)") }
            }
        }
        lines.append("---")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// A filename for the Markdown mirror: date, then a slug of the title.
    public static func filename(for note: MeetingNote) -> String {
        let date = Self.fileDate.string(from: note.startedAt ?? note.createdAt)
        let slug = Self.slug(note.title)
        return slug.isEmpty ? "\(date) meeting.md" : "\(date) \(slug).md"
    }

    static func slug(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -"))
        let cleaned = String(title.unicodeScalars.filter { allowed.contains($0) })
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return String(cleaned.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    /// mm:ss, or h:mm:ss past an hour.
    public static func clock(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private static func yaml(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    // Formatters have been thread-safe since macOS 10.9; the compiler can't know that.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let fileDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated(unsafe) private static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
