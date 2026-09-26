import Testing
import Foundation
@testable import PrompterCore

@Suite struct SpeakerLabelerTests {
    let labeler = SpeakerLabeler()

    func note(attendees: String = "Priya, Sam Lee", inPerson: Bool = false) -> MeetingNote {
        var n = MeetingNote(title: "Call", template: .blank)
        n.attendees = attendees
        n.isInPerson = inPerson
        return n
    }

    @Test func recognisesIntroductions() {
        #expect(SpeakerLabeler.introducedName(in: "Hi everyone, this is Priya from ops.") == "Priya")
        #expect(SpeakerLabeler.introducedName(in: "Sam here, can you hear me?") == "Sam")
        #expect(SpeakerLabeler.introducedName(in: "Hello, I'm Sam Lee.") == "Sam Lee")
        #expect(SpeakerLabeler.introducedName(in: "My name is Jordan and I run the venues.") == "Jordan")
        #expect(SpeakerLabeler.introducedName(in: "This is the part I like.") == nil)
        #expect(SpeakerLabeler.introducedName(in: "I'm Okay with that.") == nil)
        #expect(SpeakerLabeler.introducedName(in: "It's Friday so let's be quick.") == nil)
    }

    @Test func addressingNeedsAKnownWholeName() {
        #expect(SpeakerLabeler.addressedName(in: "Priya, what do you think?", known: ["Priya", "Sam Lee"]) == "Priya")
        #expect(SpeakerLabeler.addressedName(in: "Over to you Sam Lee.", known: ["Sam", "Sam Lee"]) == "Sam Lee")
        #expect(SpeakerLabeler.addressedName(in: "The samples look fine.", known: ["Sam"]) == nil)
        #expect(SpeakerLabeler.addressedName(in: "Anyone?", known: []) == nil)
    }

    @Test func channelDefaultsAndInPerson() {
        var n = note()
        let mic = TranscriptSegment(start: 0, end: 2, text: "Hello", channel: .microphone)
        let sys = TranscriptSegment(start: 3, end: 5, text: "Hi", channel: .system)
        #expect(n.speakerLabel(of: mic) == "Me")
        #expect(n.speakerLabel(of: sys) == "Them")
        n.isInPerson = true
        #expect(n.speakerLabel(of: mic) == "Room")
    }

    @Test func introductionLabelsTheRemoteLine() {
        let n = note()
        let seg = TranscriptSegment(start: 3, end: 6, text: "Thanks. This is Priya, I look after the venues.", channel: .system)
        #expect(labeler.suggest(for: seg, in: n) == .init(speaker: "Priya", cue: "introduced"))
    }

    @Test func addressedRemoteLineGetsTheName() {
        var n = note()
        n.transcript = [TranscriptSegment(start: 0, end: 4, text: "Priya, does that match what you see?", channel: .microphone)]
        let reply = TranscriptSegment(start: 5, end: 9, text: "Mostly, yes, but the pricing is confusing.", channel: .system)
        n.transcript.append(reply)
        #expect(labeler.suggest(for: reply, in: n) == .init(speaker: "Priya", cue: "addressed"))
    }

    @Test func addressingExpiresAndUnknownNamesAreIgnored() {
        var n = note(attendees: "")
        n.transcript = [TranscriptSegment(start: 0, end: 4, text: "Priya, does that match?", channel: .microphone)]
        let late = TranscriptSegment(start: 40, end: 44, text: "Sorry, I was on mute.", channel: .system)
        n.transcript.append(late)
        #expect(labeler.suggest(for: late, in: n) == nil, "Priya isn't a known name and 36 s have passed")
    }

    @Test func continuityKeepsTheSameSpeaker() {
        var n = note()
        n.transcript = [
            TranscriptSegment(start: 5, end: 9, text: "This is Priya.", channel: .system, speaker: "Priya", speakerIsSuggested: true),
        ]
        let next = TranscriptSegment(start: 10, end: 14, text: "And I think the alerts should go to the manager.", channel: .system)
        n.transcript.append(next)
        #expect(labeler.suggest(for: next, in: n) == .init(speaker: "Priya", cue: "continued"))
        let later = TranscriptSegment(start: 30, end: 34, text: "Anyway.", channel: .system)
        n.transcript.append(later)
        #expect(labeler.suggest(for: later, in: n) == nil, "a long gap means it could be anyone")
    }

    @Test func micLinesAreNotNamedOnACall() {
        var n = note()
        n.transcript = [TranscriptSegment(start: 0, end: 4, text: "Priya, over to you.", channel: .microphone)]
        let mine = TranscriptSegment(start: 5, end: 8, text: "Actually one more thing.", channel: .microphone)
        n.transcript.append(mine)
        #expect(labeler.suggest(for: mine, in: n) == nil)
    }

    @Test func relabelAndSetSpeakerFlowThroughToCaptures() {
        var n = note()
        let a = TranscriptSegment(start: 5, end: 9, text: "I like it.", channel: .system, speaker: "Priya", speakerIsSuggested: true)
        let b = TranscriptSegment(start: 10, end: 14, text: "But the setup is painful.", channel: .system, speaker: "Priya", speakerIsSuggested: true)
        let c = TranscriptSegment(start: 20, end: 24, text: "Fine by me.", channel: .system)
        n.transcript = [a, b, c]
        n.captures = [
            Capture(category: .feedback, text: "I like it.", at: 5, source: .detected, speaker: "Priya"),
            Capture(category: .objection, text: "But the setup is painful.", at: 10, source: .detected, speaker: "Priya"),
        ]
        #expect(n.speakers == ["Priya", "Them"])

        n.relabel("Priya", to: "Priya Nair")
        #expect(n.transcript[0].speaker == "Priya Nair")
        #expect(n.transcript[0].speakerIsSuggested == false)
        #expect(n.captures.allSatisfy { $0.speaker == "Priya Nair" })

        n.setSpeaker("Sam Lee", for: b.id)
        #expect(n.transcript[1].speaker == "Sam Lee")
        #expect(n.captures[1].speaker == "Sam Lee")
        #expect(n.captures[0].speaker == "Priya Nair")

        n.setSpeaker("Them", for: b.id)
        #expect(n.transcript[1].speaker == nil, "the channel default clears the name")

        n.relabel("Them", to: "Jordan")
        #expect(n.transcript[2].speaker == "Jordan")
        #expect(n.speakers == ["Priya Nair", "Jordan"])
    }

    @Test func knownNamesComeFromAttendeesAndLabels() {
        var n = note(attendees: "Priya; Sam Lee\nops team")
        n.transcript = [TranscriptSegment(start: 0, end: 1, text: "x", channel: .system, speaker: "Jordan")]
        #expect(labeler.knownNames(in: n) == ["Priya", "Sam Lee", "Jordan"])
    }

    @Test func oldJSONWithoutChannelsStillDecodes() throws {
        let json = """
        {"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","title":"Old","templateID":"blank","createdAt":"2026-09-01T10:00:00Z",
         "updatedAt":"2026-09-01T10:00:00Z","attendees":"","prep":[],"notes":"","wrapUp":[],
         "transcript":[{"id":"6BA7B811-9DAD-11D1-80B4-00C04FD430C8","start":0,"end":2,"text":"hi"}],
         "captures":[{"id":"6BA7B812-9DAD-11D1-80B4-00C04FD430C8","category":"feedback","text":"hi","at":0,"sentiment":"neutral","source":"detected","isKept":false,"tags":[]}],
         "tags":[]}
        """
        let note = try JSONDecoder.library.decode(MeetingNote.self, from: Data(json.utf8))
        #expect(note.transcript[0].channel == .microphone)
        #expect(note.transcript[0].speaker == nil)
        #expect(note.captures[0].speaker == nil)
        #expect(note.isInPerson == false)
    }

    @Test func detectorSkipsThePresentersOpinionsOnACall() {
        let d = InsightDetector()
        #expect(d.detect("I think this is brilliant and clear.", from: .microphone, inPerson: false) == nil)
        #expect(d.detect("I think this is brilliant and clear.", from: .microphone, inPerson: true)?.category == .feedback)
        #expect(d.detect("I'll send the plan by Friday.", from: .microphone, inPerson: false)?.category == .action)
        #expect(d.detect("I think this is brilliant and clear.", from: .system, inPerson: false)?.category == .feedback)
    }
}
