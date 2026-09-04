import Testing
@testable import PrompterCore

@Suite struct PhraseParserTests {
    let parser = PhraseParser()

    @Test func splitsLongSentenceIntoBreathSizedPhrases() {
        let text = "What we really need to understand is why customers haven't adopted the new inventory workflow despite the considerable amount of effort we've put into simplifying the experience."
        let script = parser.parse(text)
        #expect(script.phrases.count >= 3)
        #expect(script.phrases.allSatisfy { $0.words.count <= parser.options.maxWordsPerPhrase })
        #expect(script.phrases.first?.isSentenceStart == true)
        #expect(script.phrases.last?.isSentenceEnd == true)
        #expect(script.phrases.last?.pauseAfter == .paragraph)
    }

    @Test func commaGivesBeatAndPeriodGivesSentencePause() {
        let script = parser.parse("We tried the obvious fix first, and it didn't work. So we changed the workflow instead.")
        let firstComma = script.phrases.first { $0.text.hasSuffix(",") }
        #expect(firstComma?.pauseAfter == .beat)
        let firstSentenceEnd = script.phrases.first { $0.isSentenceEnd }
        #expect(firstSentenceEnd?.pauseAfter == .sentence)
    }

    @Test func shortStandaloneSentenceIsEmphatic() {
        let script = parser.parse("We learned something important from this rollout. Inventory isn't the problem. The workflow around it is.")
        let emphatic = script.phrases.first { $0.text.hasPrefix("Inventory") }
        #expect(emphatic?.emphasis == .strong)
        // The phrase before an emphatic statement gets room too.
        let before = script.phrases.first { $0.text.hasPrefix("We learned") }
        #expect(before?.pauseAfter == .emphatic)
    }

    @Test func paragraphsBecomeSections() {
        let script = parser.parse("First paragraph here.\n\nSecond paragraph here.\nThird one.")
        #expect(script.sections.count == 3)
        #expect(script.phrases.filter { $0.pauseAfter == .paragraph }.count == 3)
    }

    @Test func abbreviationsAndDecimalsDoNotEndSentences() {
        let sentences = parser.sentences(in: "Revenue grew 3.5 percent, e.g. in Q4. Dr. Smith agreed.")
        #expect(sentences.count == 2)
    }

    @Test func stripsBasicMarkdown() {
        let script = parser.parse("# Update\n\n- **Bold** point one.\n- Point [two](http://x).")
        #expect(script.sections.count == 3)
        #expect(script.phrases.contains { $0.text == "Bold point one." })
        #expect(script.phrases.contains { $0.text == "Point two." })
    }

    @Test func tinyFragmentsMergeWithNeighbours() {
        let script = parser.parse("Yes, we did it, and it worked well for everyone involved.")
        #expect(script.phrases.allSatisfy { $0.words.count >= 3 })
    }

    @Test func normalizerHandlesContractionsAndNumbers() {
        #expect(TextNormalizer.tokens(from: "We've got twenty items, 20%.") == ["we", "have", "got", "20", "items", "20", "percent"])
        #expect(TextNormalizer.normalize("Q4's") == "q4s")
    }

    @Test func estimatedDurationScalesWithStyle() {
        let script = parser.parse(String(repeating: "This is a sentence with about ten words in it, honestly. ", count: 10))
        let measured = DeliveryStyle.measured.profile.estimatedDuration(of: script)
        let energetic = DeliveryStyle.energetic.profile.estimatedDuration(of: script)
        #expect(measured > energetic * 1.3)
    }
}
