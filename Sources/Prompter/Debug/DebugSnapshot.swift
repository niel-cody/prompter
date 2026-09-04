import AppKit

/// `Prompter --snapshot out.png` renders the prompt panel to a PNG and writes a placement
/// report to `out.png.txt`, so the UI can be checked from a terminal without
/// screen-recording permission.
@MainActor
enum DebugSnapshot {
    static func run(prompt: PromptController, outputPath: String) {
        prompt.present(text: SampleScript.text, title: "Sample")
        prompt.session.jump(to: 4)
        prompt.session.start()
        // Capture partway through the phrase so the Pace Dot is mid-travel.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            let report = capture(prompt: prompt, outputPath: outputPath)
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
