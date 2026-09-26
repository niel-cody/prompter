import Testing
import Foundation
@testable import PrompterCore

@Suite struct MeetingWrapUpTests {
    func note() -> MeetingNote {
        var n = MeetingNote(title: "Pitch", template: .pitchFeedback)
        n.captures = [
            Capture(category: .feedback, text: "I like the direction", at: 5, sentiment: .positive, source: .detected),
            Capture(category: .objection, text: "worried about migration", at: 8, sentiment: .negative, source: .detected),
            Capture(category: .feedback, text: "the pricing is confusing", at: 20, sentiment: .negative, source: .detected),
            Capture(category: .question, text: "How would this work for ten venues?", at: 30, source: .detected),
            Capture(category: .action, text: "send the rollout plan by Friday", at: 40, source: .detected),
            Capture(category: .quote, text: "this would save me an hour", at: 50, sentiment: .positive, source: .marked),
            Capture(category: .decision, text: "not kept yet", at: 60, source: .detected, isKept: false),
        ]
        return n
    }

    @Test func draftsEachSectionFromMatchingCaptures() {
        var n = note()
        MeetingWrapUp.draft(&n)
        let byPrompt = Dictionary(uniqueKeysWithValues: n.wrapUp.map { ($0.prompt, $0.answer) })
        #expect(byPrompt["What landed"] == "- I like the direction (00:05)\n- \"this would save me an hour\" (00:50)")
        #expect(byPrompt["What didn't"] == "- worried about migration (00:08)\n- the pricing is confusing (00:20)")
        #expect(byPrompt["Open questions"] == "- How would this work for ten venues? (00:30)")
        #expect(byPrompt["Next steps"] == "- send the rollout plan by Friday (00:40)")
    }

    @Test func leavesWrittenAnswersAloneUnlessOverwriting() {
        var n = note()
        n.wrapUp[0].answer = "My own words."
        MeetingWrapUp.draft(&n)
        #expect(n.wrapUp[0].answer == "My own words.")
        MeetingWrapUp.draft(&n, overwrite: true)
        #expect(n.wrapUp[0].answer.hasPrefix("- I like the direction"))
    }

    @Test func ignoresUnkeptCapturesAndUnknownHeadings() {
        var n = note()
        n.wrapUp = [TemplateField(prompt: "Decisions"), TemplateField(prompt: "Weather")]
        MeetingWrapUp.draft(&n)
        #expect(n.wrapUp[0].answer == "", "the only decision is still a suggestion")
        #expect(n.wrapUp[1].answer == "")
    }

    @Test func discoveryTemplateHeadingsMapToInsightsAndQuotes() {
        var n = MeetingNote(title: "Discovery", template: .customerDiscovery)
        n.captures = [
            Capture(category: .insight, text: "they print the report every morning", at: 10, source: .detected),
            Capture(category: .quote, text: "I'd pay for that tomorrow", at: 20, source: .marked),
        ]
        MeetingWrapUp.draft(&n)
        let byPrompt = Dictionary(uniqueKeysWithValues: n.wrapUp.map { ($0.prompt, $0.answer) })
        #expect(byPrompt["Their problem in their words"] == "- \"I'd pay for that tomorrow\" (00:20)")
        #expect(byPrompt["Current workaround"]?.contains("print the report") == true)
    }
}
