import AVFoundation
import AppKit
import PrompterCore
import Speech

/// `Prompter --diagnose` prints everything that decides whether Prompter will work on this
/// Mac: OS, hardware, displays and camera placement, microphone access, and the state of
/// Apple's on-device speech model. Run it first on any machine you plan to present from.
@MainActor
enum Diagnostics {
    static func run(prompt: PromptController, hotKeys: HotKeyCenter) {
        Task {
            var out: [String] = []
            func line(_ s: String = "") { out.append(s) }

            let info = ProcessInfo.processInfo
            let v = info.operatingSystemVersion
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

            line("Prompter \(version) (build \(build))")
            line("bundle       \(Bundle.main.bundlePath)")
            line("macOS        \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
            line("hardware     \(hardwareModel()) · \(currentArchitecture())")
            line("binary       \(Self.binaryArchitectures())")
            line("requires     macOS \(Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "?")")
            line(v.majorVersion >= 26 ? "✓ OS version supported" : "✗ NEEDS macOS 26 — Prompter will not launch on this Mac")
            line()

            line("Displays (\(NSScreen.screens.count))")
            for (i, screen) in NSScreen.screens.enumerated() {
                let geo = CameraPlacement.geometry(of: screen)
                let p = PromptPlacement(display: geo)
                let frame = p.frame(size: PromptController.defaultSize, in: geo)
                let isPreferred = screen == CameraPlacement.preferredScreen()
                line("  [\(i)]\(isPreferred ? " ← prompt opens here" : "")")
                line("      frame        \(short(geo.frame))  scale \(screen.backingScaleFactor)x")
                line("      visibleFrame \(short(geo.visibleFrame))  safeAreaTop \(geo.safeAreaTop)")
                line("      notch        \(p.hasNotch ? "yes" : "no")  cameraCenterX \(p.cameraCenterX)  topEdgeY \(p.topEdgeY)")
                line("      prompt would open at \(short(frame))")
            }
            line()

            let mic = AVCaptureDevice.authorizationStatus(for: .audio)
            line("Microphone   \(describe(mic))")
            let inputs = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external],
                                                          mediaType: .audio, position: .unspecified).devices
            let defaultInput = AVCaptureDevice.default(for: .audio)
            if inputs.isEmpty {
                line("             ✗ no audio input devices found")
            } else {
                for d in inputs { line("             · \(d.localizedName)\(d.uniqueID == defaultInput?.uniqueID ? " (default)" : "")") }
            }
            line()

            line("Speech")
            line("  available  \(SpeechTranscriber.isAvailable ? "yes" : "no")")
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            line("  locale     current \(Locale.current.identifier) → \(locale?.identifier ?? "UNSUPPORTED")")
            if let locale {
                let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                                    reportingOptions: [.volatileResults, .fastResults],
                                                    attributeOptions: [.audioTimeRange])
                let status = await AssetInventory.status(forModules: [transcriber])
                line("  model      \(status)")
                if status != .installed {
                    line("             ⚠︎ downloads on first use — do this on wifi before presenting")
                }
                if let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) {
                    line("  audio      \(Int(format.sampleRate)) Hz, \(format.channelCount) ch")
                }
            }
            line()
            line("Shortcuts    \(hotKeys.registeredCount) global hot keys registered")
            line("Scripts      \(ScriptLibrary.defaultDirectory().path)")

            let report = out.joined(separator: "\n")
            print(report)
            if let i = CommandLine.arguments.firstIndex(of: "--diagnose"), i + 1 < CommandLine.arguments.count,
               !CommandLine.arguments[i + 1].hasPrefix("-") {
                try? report.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
            }
            NSApp.terminate(nil)
        }
    }

    private static func short(_ r: CGRect) -> String {
        "(\(Int(r.minX)), \(Int(r.minY))) \(Int(r.width))×\(Int(r.height))"
    }

    private static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "✓ allowed"
        case .denied: "✗ denied — System Settings › Privacy & Security › Microphone"
        case .restricted: "✗ restricted"
        case .notDetermined: "· not asked yet (Prompter asks when Voice Follow first runs)"
        @unknown default: "unknown"
        }
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [UInt8](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(decoding: chars.prefix(while: { $0 != 0 }), as: UTF8.self)
    }

    /// What this process is actually running as: native arm64, or Rosetta.
    private static func currentArchitecture() -> String {
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            return "x86_64 under Rosetta"
        }
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    private static func binaryArchitectures() -> String {
        let path = Bundle.main.executablePath ?? ""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        task.arguments = ["-archs", path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }
}
