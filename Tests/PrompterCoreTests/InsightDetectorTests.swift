import Testing
import Foundation
@testable import PrompterCore

@Suite struct InsightDetectorTests {
    let detector = InsightDetector()

    @Test func splitsSentencesKeepingTerminators() {
        let s = InsightDetector.sentences(in: "I like it. Does it scale? Not sure")
        #expect(s == ["I like it.", "Does it scale?", "Not sure"])
    }

    @Test func sentimentHandlesNegation() {
        #expect(detector.sentiment(of: "I love this, it's really clear") == .positive)
        #expect(detector.sentiment(of: "This is confusing and slow") == .negative)
        #expect(detector.sentiment(of: "I don't like this part") == .negative)
        #expect(detector.sentiment(of: "No problem at all") == .positive)
        #expect(detector.sentiment(of: "We ship on Tuesday") == .neutral)
        #expect(detector.sentiment(of: "I like the idea but the pricing is confusing") == .mixed)
    }

    @Test func classifiesFeedback() {
        let d = detector.detect("I think the onboarding flow would be nice if it was shorter.")
        #expect(d?.category == .feedback)
    }

    @Test func classifiesObjectionOverFeedback() {
        let d = detector.detect("I'm not convinced this won't break the existing workflow.")
        #expect(d?.category == .objection)
        #expect(d?.sentiment != .positive)
    }

    @Test func classifiesQuestion() {
        #expect(detector.detect("How would this work for a franchise with ten venues?")?.category == .question)
        #expect(detector.detect("What if the venue has no internet at all")?.category == .question)
    }

    @Test func decisionsAndActionsOutrankQuestions() {
        #expect(detector.detect("Okay, let's go with the second option then?")?.category == .decision)
        #expect(detector.detect("Can you send me the pricing sheet by Friday?")?.category == .action)
    }

    @Test func classifiesInsight() {
        let d = detector.detect("In practice our customers end up printing the report every morning.")
        #expect(d?.category == .insight)
    }

    @Test func negativeButIsAnObjection() {
        let d = detector.detect("It looks fine but honestly the setup is painful and slow.")
        #expect(d?.category == .feedback || d?.category == .objection)
        let plain = detector.detect("The colour is fine but the export is broken and painful.")
        #expect(plain?.category == .objection)
        #expect(plain?.cue == "but + negative")
    }

    @Test func strongFeelingWithoutCueIsSentiment() {
        let d = detector.detect("Honestly this is brilliant, genuinely excellent work.")
        #expect(d?.category == .sentiment)
        #expect(d?.sentiment == .positive)
    }

    @Test func ignoresShortAndNeutralSentences() {
        #expect(detector.detect("Why?") == nil)
        #expect(detector.detect("Next slide please.") == nil)
        #expect(detector.detect("The meeting starts at ten on the third floor.") == nil)
    }

    @Test func detectsAcrossABlock() {
        let block = "Thanks for coming. I like the direction. But I'm worried about the migration. Can you share the plan by Monday?"
        let found = detector.detect(in: block)
        #expect(found.map(\.category) == [.feedback, .objection, .action])
    }
}
