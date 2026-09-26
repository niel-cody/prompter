import Testing
import Foundation
@testable import PrompterCore

@Suite struct MeetingNoteTests {
    func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("PrompterMeetings-\(UUID().uuidString)")
    }

    func sampleNote() -> MeetingNote {
        var note = MeetingNote(title: "Inventory pitch: ops team", template: .pitchFeedback,
                               createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        note.startedAt = note.createdAt
        note.endedAt = note.createdAt.addingTimeInterval(754)
        note.attendees = "Sam, Priya"
        note.prep[0].answer = "Automatic reorder points for every venue."
        note.notes = "Priya nodded a lot at the forecast slide."
        note.transcript = [
            TranscriptSegment(start: 0, end: 4, text: "Thanks for coming."),
            TranscriptSegment(start: 61, end: 66, text: "I like the forecast, but the setup looks painful."),
        ]
        note.captures = [
            Capture(category: .feedback, text: "I like the forecast", at: 61, sentiment: .positive, source: .detected, isKept: true),
            Capture(category: .objection, text: "the setup looks painful", at: 63, sentiment: .negative, source: .detected, isKept: true),
            Capture(category: .quote, text: "This would save me an hour a day", at: 400, sentiment: .positive, source: .marked, isKept: true, tags: ["ops"]),
            Capture(category: .question, text: "What about multi-site?", at: 500, source: .detected, isKept: false),
        ]
        note.wrapUp[0].answer = "The forecast."
        return note
    }

    @Test func templateSeedsPrepAndWrapUp() {
        let note = MeetingNote(title: "x", template: .customerDiscovery)
        #expect(note.prep.map(\.prompt) == MeetingTemplate.customerDiscovery.prepPrompts)
        #expect(note.wrapUp.map(\.prompt) == MeetingTemplate.customerDiscovery.wrapUpSections)
        #expect(note.tags == ["discovery", "customer"])
        #expect(MeetingTemplate.builtIn.map(\.id).contains("blank"))
    }

    @Test func recentTranscriptWindow() {
        let note = sampleNote()
        #expect(note.recentTranscript(before: 66, window: 10) == "I like the forecast, but the setup looks painful.")
        #expect(note.recentTranscript(before: 70, window: 200).hasPrefix("Thanks for coming."))
        #expect(note.recentTranscript(before: 30, window: 5) == "")
    }

    @Test func overallSentimentAndCounts() {
        let note = sampleNote()
        #expect(note.overallSentiment == .mixed)
        #expect(note.categoryCounts[.feedback] == 1)
        #expect(note.categoryCounts[.question] == nil, "unkept suggestions don't count")
        #expect(note.suggestedCaptures.count == 1)
    }

    @Test func markdownHasFrontMatterAndCategoryHeadings() {
        let md = MeetingMarkdown.render(sampleNote())
        #expect(md.hasPrefix("---\ntitle: \"Inventory pitch: ops team\"\n"))
        #expect(md.contains("template: pitch-feedback"))
        #expect(md.contains("duration_seconds: 754"))
        #expect(md.contains("tags: [pitch, prompter]"))
        #expect(md.contains("sentiment: mixed"))
        #expect(md.contains("captures: 3"))
        #expect(md.contains("  feedback: 1\n  objection: 1\n  quote: 1"))
        #expect(md.contains("# Inventory pitch: ops team"))
        #expect(md.contains("## Prep\n\n**What am I pitching, in one sentence?**  \nAutomatic reorder points"))
        #expect(md.contains("## Notes\n\nPriya nodded"))
        #expect(md.contains("### Feedback\n\n- `01:01` _positive_ I like the forecast"))
        #expect(md.contains("### Objections\n\n- `01:03` _negative_ the setup looks painful"))
        #expect(md.contains("### Quotes\n\n- `06:40` _positive_ \"This would save me an hour a day\" #ops"))
        #expect(md.contains("## Suggested\n\n_Flagged automatically; not yet reviewed._\n\n- `08:20` **Question** What about multi-site?"))
        #expect(md.contains("## Wrap-up\n\n### What landed\n\nThe forecast."))
        #expect(md.contains("mode: call"))
        #expect(md.contains("speakers: [\"Me\"]"))
        #expect(md.contains("## Transcript\n\n**Me**  \n`00:00` Thanks for coming.  \n`01:01` I like"))
    }

    @Test func markdownGroupsTranscriptBySpeaker() {
        var note = MeetingNote(title: "Call", template: .blank)
        note.transcript = [
            TranscriptSegment(start: 0, end: 2, text: "Hi all.", channel: .microphone),
            TranscriptSegment(start: 3, end: 5, text: "This is Priya.", channel: .system, speaker: "Priya", speakerIsSuggested: true),
            TranscriptSegment(start: 6, end: 8, text: "I like it.", channel: .system, speaker: "Priya", speakerIsSuggested: true),
            TranscriptSegment(start: 9, end: 10, text: "Fine.", channel: .system),
        ]
        note.captures = [Capture(category: .feedback, text: "I like it.", at: 6, sentiment: .positive, source: .detected, speaker: "Priya")]
        let md = MeetingMarkdown.render(note)
        #expect(md.contains("speakers: [\"Me\", \"Priya\", \"Them\"]"))
        #expect(md.contains("**Me**  \n`00:00` Hi all.  \n\n**Priya** _(suggested)_  \n`00:03` This is Priya.  \n`00:06` I like it.  \n\n**Them**  \n`00:09` Fine.  "))
        #expect(md.contains("- `00:06` _positive_ I like it. — Priya"))
    }

    @Test func markdownSkipsEmptySections() {
        let note = MeetingNote(title: "", template: .blank)
        let md = MeetingMarkdown.render(note)
        #expect(md.contains("# Untitled meeting"))
        #expect(!md.contains("## Prep"))
        #expect(!md.contains("## Captures"))
        #expect(!md.contains("## Transcript"))
        #expect(!md.contains("duration_seconds"))
    }

    @Test func filenameIsDateThenSlug() {
        var note = sampleNote()
        #expect(MeetingMarkdown.filename(for: note).hasSuffix(" Inventory pitch ops team.md"))
        #expect(MeetingMarkdown.filename(for: note).hasPrefix("2026-"))
        note.title = "   "
        #expect(MeetingMarkdown.filename(for: note).hasSuffix(" meeting.md"))
    }

    @Test func clockFormatting() {
        #expect(MeetingMarkdown.clock(0) == "00:00")
        #expect(MeetingMarkdown.clock(754) == "12:34")
        #expect(MeetingMarkdown.clock(3725) == "1:02:05")
    }

    @Test func storeRoundTripsAndMirrorsMarkdown() throws {
        let dir = tempDir()
        let md = tempDir()
        let store = MeetingStore(directory: dir, markdownDirectory: md)
        let saved = try store.save(sampleNote())
        let reloaded = MeetingStore(directory: dir, markdownDirectory: md)
        #expect(reloaded.all().count == 1)
        #expect(reloaded.note(id: saved.id)?.captures.count == 4)
        let file = store.markdownURL(for: saved)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("### Quotes"))
    }

    @Test func retitleReplacesMarkdownFile() throws {
        let dir = tempDir()
        let store = MeetingStore(directory: dir)
        var note = try store.save(sampleNote())
        let first = store.markdownURL(for: note)
        note.title = "Renamed"
        try store.save(note)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: store.markdownURL(for: note).path))
    }

    @Test func deleteRemovesBothFiles() throws {
        let dir = tempDir()
        let store = MeetingStore(directory: dir)
        let note = try store.save(sampleNote())
        let file = store.markdownURL(for: note)
        try store.delete(id: note.id)
        #expect(store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(MeetingStore(directory: dir).all().isEmpty)
    }

    @Test func searchLooksInCapturesAndTranscript() throws {
        let store = MeetingStore(directory: tempDir())
        try store.save(sampleNote())
        #expect(store.search("hour a day").count == 1)
        #expect(store.search("painful").count == 1)
        #expect(store.search("zebra").isEmpty)
    }

    @Test func changingMarkdownFolderRewritesEverything() throws {
        let store = MeetingStore(directory: tempDir())
        let note = try store.save(sampleNote())
        let vault = tempDir()
        try store.setMarkdownDirectory(vault)
        #expect(store.markdownURL(for: note).path.hasPrefix(vault.path))
        #expect(FileManager.default.fileExists(atPath: store.markdownURL(for: note).path))
    }
}
