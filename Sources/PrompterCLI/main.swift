import Foundation
import PrompterCore

// Developer tool: inspect how a script is phrased and paced.
//   swift run prompter-cli path/to/script.txt [style]
//   echo "text" | swift run prompter-cli - [style]
let args = CommandLine.arguments.dropFirst()
guard let source = args.first else {
    print("usage: prompter-cli <file|-> [measured|professional|conversational|energetic]")
    exit(1)
}
let text: String
if source == "-" {
    text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
} else {
    text = try String(contentsOfFile: source, encoding: .utf8)
}
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
