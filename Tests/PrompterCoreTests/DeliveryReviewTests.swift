import Testing
import Foundation
@testable import PrompterCore

@Suite struct DeliveryReviewTests {
    let script = PhraseParser().parse("""
    Thanks for making time today. I want to share a quick update on where we've landed with the inventory rollout, and what we're changing next.

    We learned something important from this rollout. Inventory isn't the problem. The workflow around it is.

    Venues were counting stock correctly, but the numbers weren't reaching the people making ordering decisions. So we've simplified the flow: one count, one place, and a summary that lands in the manager's inbox every morning.
    """)
    let profile = DeliveryStyle.professional.profile

    /// Simulate a run where each phrase takes `speed` × its planned time, with pauses honoured
    /// according to `takePauses`.
    func simulate(speed: Double, takePauses: Bool, sectionSpeed: [Int: Double] = [:]) -> DeliveryLog {
        let plan = PacePlan(script: script, profile: profile)
        var log = DeliveryLog()
        var t: TimeInterval = 0
        log.start(at: t)
        for phrase in script.phrases {
            let timing = plan.timing(at: phrase.id)!
            let s = sectionSpeed[phrase.sectionIndex] ?? speed
            log.enter(phrase: phrase.id, at: t)
            log.noteSpeech(at: t + 0.1)
            let speak = timing.speaking * s
            log.noteSpeech(at: t + speak)
            t += speak + (takePauses ? timing.pause : 0.1)
        }
        log.end(at: t)
        return log
    }

    @Test func steadyProfessionalRunScoresHighly() {
        let plan = PacePlan(script: script, profile: profile)
        let review = DeliveryReview(log: simulate(speed: 1.0, takePauses: true), script: script, plan: plan)
        #expect(review.hasEnoughData)
        #expect(review.score >= 9)
        #expect(review.completion == 1)
        #expect(review.pausesTaken == review.pausesSuggested)
        #expect(review.rushedSection == nil)
        #expect(abs(review.averageWordsPerMinute! - review.targetWordsPerMinute) < 12)
    }

    @Test func rushingAndSkippingPausesIsCalledOut() {
        let plan = PacePlan(script: script, profile: profile)
        let review = DeliveryReview(log: simulate(speed: 0.7, takePauses: false), script: script, plan: plan)
        #expect(review.hasEnoughData)
        #expect(review.score < 7)
        #expect(review.pausesTaken < review.pausesSuggested)
        #expect(review.notes.contains { $0.hasPrefix("Try giving") })
        #expect(review.averageWordsPerMinute! > review.targetWordsPerMinute * 1.2)
    }

    @Test func oneFastSectionIsIdentified() {
        let plan = PacePlan(script: script, profile: profile)
        let review = DeliveryReview(log: simulate(speed: 1.0, takePauses: true, sectionSpeed: [2: 0.6]), script: script, plan: plan)
        #expect(review.rushedSection == 2)
        #expect(review.notes.contains { $0.contains("sped up") })
    }

    @Test func shortSessionDeclinesToJudge() {
        let plan = PacePlan(script: script, profile: profile)
        var log = DeliveryLog()
        log.start(at: 0)
        log.enter(phrase: 0, at: 0)
        log.end(at: 3)
        let review = DeliveryReview(log: log, script: script, plan: plan)
        #expect(!review.hasEnoughData)
        #expect(review.headline == "Too short to review")
    }
}
