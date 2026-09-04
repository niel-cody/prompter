import Testing
import Foundation
@testable import PrompterCore

@Suite struct PaceTests {
    let script = PhraseParser().parse("We learned something important from this rollout. Inventory isn't the problem. The workflow around it is.")

    @Test func planCoversEveryPhrase() {
        let plan = PacePlan(script: script, profile: DeliveryStyle.professional.profile)
        #expect(plan.timings.count == script.phrases.count)
        #expect(plan.totalDuration > 0)
        #expect(plan.timings.allSatisfy { $0.speaking > 0 })
    }

    @Test func conductorMovesThroughSpeakingThenPauseThenWaits() {
        let timing = PhraseTiming(phraseIndex: 0, speaking: 2.0, pause: 1.0)
        #expect(PaceConductor.phase(elapsed: 0, timing: timing) == .speaking(progress: 0))
        #expect(PaceConductor.phase(elapsed: 1, timing: timing) == .speaking(progress: 0.5))
        #expect(PaceConductor.phase(elapsed: 2.5, timing: timing) == .pausing(progress: 0.5))
        #expect(PaceConductor.phase(elapsed: 3.5, timing: timing) == .waiting(for: 0.5))
        #expect(PaceConductor.phase(elapsed: -1, timing: timing) == .speaking(progress: 0))
    }

    @Test func emphaticPhraseGetsLongerPause() {
        let plan = PacePlan(script: script, profile: DeliveryStyle.professional.profile)
        let emphatic = script.phrases.first { $0.pauseAfter == .emphatic }!
        let normal = script.phrases.first { $0.pauseAfter == .sentence } ?? script.phrases.last!
        #expect(plan.timing(at: emphatic.id)!.pause >= plan.timing(at: normal.id)!.pause || normal.pauseAfter == .paragraph)
    }

    @Test func deliveryLogTracksVisitsAndPauses() {
        var log = DeliveryLog()
        log.start(at: 0)
        log.enter(phrase: 0, at: 0)
        log.enter(phrase: 1, at: 3)
        log.pause(at: 4)
        log.resume(at: 10, phrase: 1)
        log.enter(phrase: 2, at: 12)
        log.end(at: 15)
        #expect(log.visits.count == 4)
        #expect(log.visits[0].duration == 3)
        #expect(log.pausedDuration == 6)
        #expect(log.activeDuration == 9)
        #expect(log.furthestPhrase == 2)
    }
}
