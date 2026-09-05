import AppKit
import SwiftUI
import PrompterCore

/// `Prompter --snapshot out.png` renders the prompt panel to a PNG and writes a placement
/// report to `out.png.txt`, so the UI can be checked from a terminal without
/// screen-recording permission.
@MainActor
private final class FollowTrace {
    var lastIndex = -1
}

@MainActor
enum DebugSnapshot {
    /// `--follow-test recording.aiff`: runs the sample script through the real live pipeline
    /// (AVAudioEngine → converter → SpeechAnalyzer → matcher → session) with the file as
    /// the "microphone", then prints the review. Exercises everything but the mic itself.
    static func runFollowTest(prompt: PromptController, audioPath: String) {
        prompt.voice.speech.testAudioFile = URL(fileURLWithPath: audioPath)
        prompt.present(text: SampleScript.text, title: "Follow test")
        let session = prompt.session
        let trace = FollowTrace()
        let started = Date()
        // Poll the session so the trace doesn't need hooks in product code.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                if session.currentIndex != trace.lastIndex {
                    trace.lastIndex = session.currentIndex
                    let t = String(format: "%5.1f", Date().timeIntervalSince(started))
                    print("\(t)s → phrase \(trace.lastIndex): \(session.currentPhrase?.text ?? "")  [speech: \(prompt.voice.speech.state)]")
                }
            }
        }
        let original = session.onFinished
        session.onFinished = {
            timer.invalidate()
            original?()
            let review = DeliveryReview(log: session.log, script: session.script, plan: session.plan, styleName: session.style.displayName)
            print("\nFINISHED after \(String(format: "%.1f", Date().timeIntervalSince(started)))s — \(review.headline) (\(review.score)/10)")
            review.notes.forEach { print(" - \($0)") }
            NSApp.terminate(nil)
        }
        session.start()
        // Safety net: bail out if the audio never arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            print("follow-test timed out; speech state \(prompt.voice.speech.state)")
            NSApp.terminate(nil)
        }
    }

    /// `--snapshot-window library|settings|onboarding out.png`: shows the window, captures it.
    static func runWindow(_ which: String, library: LibraryWindowController, settings: SettingsWindowController,
                          model: LibraryModel, outputPath: String) {
        let expectedTitle: String
        switch which {
        case "library":
            expectedTitle = "Prompter"
            if model.documents.isEmpty { model.createNew(title: "Sample: inventory update", text: SampleScript.text) }
            model.selectedID = model.documents.first?.id
            library.show()
        case "settings": expectedTitle = "Prompter Settings"; settings.show()
        case "onboarding": expectedTitle = "Welcome to Prompter"; library.showOnboarding()
        default: print("unknown window \(which)"); NSApp.terminate(nil); return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if let window = NSApp.windows.first(where: { $0.title == expectedTitle && $0.isVisible }),
               let view = window.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: outputPath))
                    print("window snapshot written \(outputPath) \(rep.pixelsWide)x\(rep.pixelsHigh) title=\(window.title)")
                }
            } else {
                print("window snapshot: no window")
            }
            NSApp.terminate(nil)
        }
    }

    /// `Prompter --snapshot-review out.png` renders the review card for a simulated session.
    static func runReview(prompt: PromptController, outputPath: String) {
        let script = PhraseParser().parse(SampleScript.text)
        let plan = PacePlan(script: script, profile: DeliveryStyle.professional.profile)
        var log = DeliveryLog()
        var t: TimeInterval = 0
        log.start(at: t)
        for phrase in script.phrases {
            let timing = plan.timing(at: phrase.id)!
            // Section 2 rushed; two emphatic pauses skipped.
            let speed = phrase.sectionIndex == 2 ? 0.65 : 0.98
            let skipPause = phrase.pauseAfter == .emphatic && phrase.id % 2 == 0
            log.enter(phrase: phrase.id, at: t)
            log.noteSpeech(at: t + 0.1)
            let speak = timing.speaking * speed
            log.noteSpeech(at: t + speak)
            t += speak + (skipPause ? 0.1 : timing.pause)
        }
        log.end(at: t)
        let review = DeliveryReview(log: log, script: script, plan: plan)
        let view = ReviewView(review: review, title: "Inventory rollout update", onPresentAgain: {}, onClose: {})
        let renderer = ImageRenderer(content: view.frame(width: 440).background(Color(nsColor: .windowBackgroundColor)))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: outputPath))
            print("review snapshot written \(outputPath)")
        }
        print(review.headline); review.notes.forEach { print(" - \($0)") }
        prompt.reviewWindow.show(review: review, title: "Inventory rollout update") {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let w = NSApp.windows.first(where: { $0.title == "Delivery Review" }), let host = w.contentViewController as? NSHostingController<ReviewView> {
                let fit = host.sizeThatFits(in: NSSize(width: 440, height: 2000))
                print("review window content \(w.contentLayoutRect.size) fitting \(fit) cropped=\(fit.height > w.contentLayoutRect.height + 1)")
            }
            NSApp.terminate(nil)
        }
    }

    static func run(prompt: PromptController, hotKeys: HotKeyCenter, outputPath: String) {
        prompt.present(text: SampleScript.text, title: "Sample")
        prompt.session.jump(to: 4)
        prompt.session.start()
        // Capture partway through the phrase so the Pace Dot is mid-travel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            let report = capture(prompt: prompt, outputPath: outputPath)
                + "\nhotKeysRegistered   \(hotKeys.registeredCount)"
                + "\nspeech.state        \(prompt.voice.speech.state)"
            print(report)
            try? report.write(toFile: outputPath + ".txt", atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }

    private static func capture(prompt: PromptController, outputPath: String) -> String {
        guard let panel = prompt.debugPanel, let view = panel.contentView else {
            return "snapshot: no panel"
        }
        let screen = panel.screen ?? NSScreen.main!
        let placement = CameraPlacement(screen: screen)
        var lines: [String] = []
        lines.append("screen.frame        \(screen.frame)")
        lines.append("screen.visibleFrame \(screen.visibleFrame)")
        lines.append("safeAreaInsets      \(screen.safeAreaInsets)")
        lines.append("hasNotch            \(placement.hasNotch)")
        lines.append("cameraCenterX       \(placement.cameraCenterX)  topEdgeY \(placement.topEdgeY)")
        lines.append("panel.frame         \(panel.frame)")
        lines.append("panel.midX          \(panel.frame.midX)  gapBelowTop \(placement.topEdgeY - panel.frame.maxY)")
        lines.append("panel.level         \(panel.level.rawValue)  visible \(panel.isVisible)  key \(panel.isKeyWindow)")
        lines.append("app.isActive        \(NSApp.isActive)")

        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                do {
                    try data.write(to: URL(fileURLWithPath: outputPath))
                    lines.append("snapshot written \(outputPath) \(rep.pixelsWide)x\(rep.pixelsHigh)")
                } catch {
                    lines.append("snapshot failed: \(error)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
