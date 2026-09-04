import AVFoundation
import Foundation
import PrompterCore
import Speech

// Developer tool.
//   prompter-cli parse  <file|-> [style]        phrase + pacing breakdown
//   prompter-cli follow <script> <audio-file>    run on-device recognition over a recording
//                                                and trace the matcher's decisions

func readText(_ source: String) throws -> String {
    if source == "-" {
        return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
    return try String(contentsOfFile: source, encoding: .utf8)
}

func runParse(_ args: [String]) throws {
    guard let source = args.first else { print("usage: prompter-cli parse <file|-> [style]"); exit(1) }
    let text = try readText(source)
    let style = args.dropFirst().first.flatMap(DeliveryStyle.init(rawValue:)) ?? .professional
    let script = PhraseParser().parse(text)
    let profile = style.profile
    var elapsed: TimeInterval = 0
    for phrase in script.phrases {
        let dur = profile.speakingDuration(of: phrase)
        let pause = profile.pauseDuration(phrase.pauseAfter)
        let marker = phrase.emphasis == .strong ? "★" : " "
        let pauseLabel = phrase.pauseAfter == .none ? "" : "  ⏸ \(phrase.pauseAfter.rawValue) \(String(format: "%.2fs", pause))"
        print(String(format: "%6.1fs %@ §%d s%d  %@%@", elapsed, marker, phrase.sectionIndex, phrase.sentenceIndex, phrase.text, pauseLabel))
        elapsed += dur + pause
    }
    print("\n\(script.phrases.count) phrases, \(script.wordCount) words, ~\(Int(elapsed.rounded())) s at \(style.displayName) (\(Int(profile.wordsPerMinute)) wpm)")
}

@MainActor
final class FollowTracer {
    let script: PresentationScript
    var matcher: ScriptMatcher
    var committed: [String] = []
    var lastPhrase: Int? = nil

    init(script: PresentationScript) {
        self.script = script
        matcher = ScriptMatcher(script: script)
    }

    func handle(text: String, isFinal: Bool, end: TimeInterval) {
        let tokens = TextNormalizer.tokens(from: text)
        let all: [String]
        if isFinal { committed += tokens; all = committed } else { all = committed + tokens }
        let r = matcher.update(spoken: all)
        let t = String(format: "%5.1f", end)
        let kind = isFinal ? "FINAL" : "  vol"
        var line = "\(t) \(kind) \(text)"
        if let r, r.phraseIndex != lastPhrase {
            lastPhrase = r.phraseIndex
            line += "\n        → phrase \(r.phraseIndex) (score \(String(format: "%.1f", r.score))): \(script.phrases[r.phraseIndex].text)"
        }
        print(line)
    }
}

@MainActor
func runFollow(_ args: [String]) async throws {
    guard args.count >= 2 else { print("usage: prompter-cli follow <script> <audio-file>"); exit(1) }
    let script = PhraseParser().parse(try readText(args[0]))
    let audioURL = URL(fileURLWithPath: args[1])

    guard SpeechTranscriber.isAvailable else { print("SpeechTranscriber unavailable"); exit(2) }
    let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) ?? Locale(identifier: "en_US")
    print("locale \(locale.identifier)")
    let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                        reportingOptions: [.volatileResults, .fastResults],
                                        attributeOptions: [.audioTimeRange])
    let status = await AssetInventory.status(forModules: [transcriber])
    print("assets \(status)")
    if status != .installed, let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
        print("downloading speech assets…")
        try await req.downloadAndInstall()
    }

    let tracer = FollowTracer(script: script)

    let file = try AVAudioFile(forReading: audioURL)
    print("audio \(String(format: "%.1f", Double(file.length) / file.processingFormat.sampleRate))s @ \(Int(file.processingFormat.sampleRate))Hz")
    let analyzer = SpeechAnalyzer(modules: [transcriber], options: nil)

    let consume = Task { @MainActor in
        for try await result in transcriber.results {
            tracer.handle(text: String(result.text.characters), isFinal: result.isFinal, end: result.range.end.seconds)
        }
    }
    try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    try await consume.value
    print("\nfinal phrase \(tracer.lastPhrase.map(String.init) ?? "none") of \(script.phrases.count - 1)")
}

let argv = Array(CommandLine.arguments.dropFirst())
switch argv.first {
case "follow":
    try await runFollow(Array(argv.dropFirst()))
case "parse":
    try runParse(Array(argv.dropFirst()))
case .some(let first) where first != "-h" && first != "--help":
    try runParse(argv)
default:
    print("usage: prompter-cli parse <file|-> [style] | follow <script> <audio-file>")
}
