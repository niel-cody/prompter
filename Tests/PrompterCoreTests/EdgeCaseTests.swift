import Testing
import Foundation
@testable import PrompterCore

@Suite struct EdgeCaseTests {
    let paragraph = "Venues were counting stock correctly, but the numbers weren't reaching the people making ordering decisions. So we've simplified the flow: one count, one place, and a summary that lands in the manager's inbox every morning. "

    @Test func emptyAndWhitespaceScriptsProduceNoPhrases() {
        #expect(PhraseParser().parse("").isEmpty)
        #expect(PhraseParser().parse("  \n\n \t ").isEmpty)
        var m = ScriptMatcher(script: PhraseParser().parse(""))
        #expect(m.update(spoken: ["hello"]) == nil)
    }

    @Test func singleWordScriptWorksEndToEnd() {
        let script = PhraseParser().parse("Hello.")
        #expect(script.phrases.count == 1)
        #expect(script.phrases[0].pauseAfter == .paragraph)
        let plan = PacePlan(script: script, profile: DeliveryStyle.professional.profile)
        #expect(plan.totalDuration > 0)
        var m = ScriptMatcher(script: script)
        // A one-word script can't clear the cold-start bar on its own; that's the safe outcome.
        #expect(m.update(spoken: ["hello"])?.phraseIndex ?? 0 == 0)
        #expect(script.nextSectionStart(after: 0) == nil)
        #expect(script.previousSectionStart(before: 0) == 0)
    }

    @Test func punctuationOnlyAndOddInputDoNotCrash() {
        for text in ["...", "— — —", "!!!", "(", "a", "42", "1,000,000.", "e.g. i.e. etc.", "\u{FEFF}", "😀 😀"] {
            let script = PhraseParser().parse(text)
            _ = PacePlan(script: script, profile: DeliveryStyle.energetic.profile)
            var m = ScriptMatcher(script: script)
            _ = m.update(spoken: TextNormalizer.tokens(from: text))
        }
    }

    @Test func veryLongScriptParsesAndMatchesQuickly() {
        let text = (0..<60).map { "Section \($0). " + paragraph + "\n" }.joined(separator: "\n")
        let start = Date()
        let script = PhraseParser().parse(text)
        let parseTime = Date().timeIntervalSince(start)
        #expect(script.wordCount > 2_000)
        #expect(script.sections.count == 60)
        #expect(parseTime < 1.0)

        // Speaker starts at section 40 with nothing anchored: whole-script search every update.
        var m = ScriptMatcher(script: script)
        let spoken = TextNormalizer.tokens(from: "Section 40. " + paragraph + paragraph)
        var tokens: [String] = []
        let matchStart = Date()
        var last: ScriptMatcher.Result?
        for t in spoken {
            tokens.append(t)
            if let r = m.update(spoken: tokens) { last = r }
        }
        let matchTime = Date().timeIntervalSince(matchStart)
        #expect(matchTime < 1.5)
        #expect(last != nil)
        // Section 40 is the 41st section; the match should be somewhere in it or the next.
        if let last {
            let section = script.phrases[last.phraseIndex].sectionIndex
            #expect((39...41).contains(section))
        }
    }

    @Test func skippingSeveralParagraphsRecovers() {
        let text = (0..<6).map { "Part \($0) begins here. " + paragraph }.joined(separator: "\n\n")
        let script = PhraseParser().parse(text)
        var m = ScriptMatcher(script: script)
        var tokens = TextNormalizer.tokens(from: "Part 0 begins here. Venues were counting stock correctly,")
        _ = m.update(spoken: tokens)
        let before = m.currentPhrase!
        // Jump straight to part 4.
        for t in TextNormalizer.tokens(from: "Part 4 begins here. Venues were counting stock correctly, but the numbers") {
            tokens.append(t)
            _ = m.update(spoken: tokens)
        }
        let after = m.currentPhrase!
        #expect(script.phrases[after].sectionIndex == 4)
        #expect(after > before)
    }

    @Test func reviewHandlesSessionWithNoSpeechTimestamps() {
        let script = PhraseParser().parse(paragraph + paragraph + paragraph)
        let plan = PacePlan(script: script, profile: DeliveryStyle.professional.profile)
        var log = DeliveryLog()
        var t: TimeInterval = 0
        log.start(at: t)
        for p in script.phrases {
            log.enter(phrase: p.id, at: t)
            t += plan.timing(at: p.id)!.total
        }
        log.end(at: t)
        let review = DeliveryReview(log: log, script: script, plan: plan)
        #expect(review.hasEnoughData)
        #expect(review.pausesSuggested == 0)      // manual mode: nothing to say about pauses
        #expect(!review.notes.contains { $0.contains("pauses") })
    }
}
