import Testing
@testable import PrompterCore

@Suite struct ScriptMatcherTests {
    let text = """
    Thanks for making time today. I want to share a quick update on where we've landed with the inventory rollout, and what we're changing next.

    We learned something important from this rollout. Inventory isn't the problem. The workflow around it is.

    Venues were counting stock correctly, but the numbers weren't reaching the people making ordering decisions. So we've simplified the flow: one count, one place, and a summary that lands in the manager's inbox every morning.

    Early results are encouraging. Adoption has doubled in the pilot group, and support tickets about stock levels have dropped by a third.
    """

    var script: PresentationScript { PhraseParser().parse(text) }

    /// Simulates a transcript arriving word by word, returning the phrase index after each word.
    func trace(_ spoken: String, matcher: inout ScriptMatcher) -> [Int?] {
        var tokens: [String] = []
        var out: [Int?] = []
        for t in TextNormalizer.tokens(from: spoken) {
            tokens.append(t)
            out.append(matcher.update(spoken: tokens)?.phraseIndex)
        }
        return out
    }

    @Test func followsExactReadingPhraseByPhrase() {
        var m = ScriptMatcher(script: script)
        let s = script
        let phrases = trace(text, matcher: &m).compactMap { $0 }
        // Visits every phrase in order (never goes backwards) and reaches the end.
        #expect(phrases.first == 0)
        #expect(phrases.last == s.phrases.count - 1)
        #expect(zip(phrases, phrases.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(Set(phrases).count == s.phrases.count)
    }

    @Test func holdsDuringImprovisation() {
        var m = ScriptMatcher(script: script)
        _ = trace("Thanks for making time today. I want to share a quick update", matcher: &m)
        let before = m.currentPhrase
        let during = trace("and honestly this has been a really interesting few weeks for the whole team you know", matcher: &m)
        #expect(during.compactMap { $0 }.allSatisfy { $0 == before })
        // Then picks up again when the script resumes (those words are the next phrase).
        let after = trace("on where we've landed with the inventory rollout", matcher: &m)
        #expect(after.last == before.map { $0 + 1 })
    }

    @Test func catchesUpWhenSpeakerSkipsSentence() {
        var m = ScriptMatcher(script: script)
        _ = trace("We learned something important from this rollout.", matcher: &m)
        // Skips "Inventory isn't the problem. The workflow around it is." entirely.
        let r = trace("Venues were counting stock correctly, but the numbers weren't reaching", matcher: &m)
        let target = script.phrases.first { $0.text.hasPrefix("but the numbers") }!.id
        #expect(r.last == target)
    }

    @Test func goesBackWhenSpeakerRestartsEarlierLine() {
        var m = ScriptMatcher(script: script)
        _ = trace("Venues were counting stock correctly, but the numbers weren't reaching the people making ordering decisions.", matcher: &m)
        let r = trace("Sorry, let me say that again. We learned something important from this rollout.", matcher: &m)
        let target = script.phrases.first { $0.text.hasPrefix("We learned") }!.id
        #expect(r.last == target)
    }

    @Test func repeatingAPhraseDoesNotRunAhead() {
        var m = ScriptMatcher(script: script)
        _ = trace("Inventory isn't the problem.", matcher: &m)
        let r = trace("Inventory isn't the problem.", matcher: &m)
        let target = script.phrases.first { $0.text.hasPrefix("Inventory") }!.id
        #expect(r.last == target)
    }

    @Test func findsPositionWhenStartingMidway() {
        var m = ScriptMatcher(script: script)
        let r = trace("Early results are encouraging. Adoption has doubled in the pilot group", matcher: &m)
        let target = script.phrases.first { $0.text.hasPrefix("Adoption") }!.id
        #expect(r.last == target)
    }

    @Test func toleratesRecognitionSlipsAndParaphrase() {
        var m = ScriptMatcher(script: script)
        // "venues" -> "venus", "weren't" -> "were not", dropped "correctly", "reaching" -> "reachin"
        let r = trace("The venus were counting stock, but the numbers were not reachin the people making ordering decisions", matcher: &m)
        let target = script.phrases.first { $0.text.hasPrefix("but the numbers") }!.id
        #expect(r.last == target)
    }

    @Test func ignoresUnrelatedChatterFromColdStart() {
        var m = ScriptMatcher(script: script)
        let r = trace("hello can everyone hear me okay great let's get going", matcher: &m)
        #expect(r.compactMap { $0 }.isEmpty)
    }

    @Test func resetReanchorsAfterManualJump() {
        var m = ScriptMatcher(script: script)
        _ = trace("Thanks for making time today.", matcher: &m)
        let target = script.phrases.first { $0.text.hasPrefix("Early results") }!.id
        m.reset(toPhrase: target)
        let r = trace("Early results are encouraging.", matcher: &m)
        #expect(r.last == target)
    }

    @Test func similarityRewardsNearMisses() {
        #expect(ScriptMatcher.similarity(spoken: "inventory", script: "inventory") == 1.0)
        #expect(ScriptMatcher.similarity(spoken: "the", script: "the") == 0.5)
        #expect(ScriptMatcher.similarity(spoken: "reachin", script: "reaching") > 0.5)
        #expect(ScriptMatcher.similarity(spoken: "cat", script: "inventory") < 0)
    }
}
