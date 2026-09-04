# Prompter — notes for Claude

Native macOS 26 teleprompter + speaking coach. Swift 6 / SwiftUI / AppKit, SwiftPM only
(no .xcodeproj). Open `Package.swift` in Xcode if you want the IDE.

## Build, test, run

- `Scripts/build-app.sh debug [--run]` — builds and assembles `build/Prompter.app` (ad-hoc signed). Always launch the *bundle*, not the bare binary, when microphone/speech permission matters.
- `swift test` — PrompterCore unit tests (parser, pacing, matcher, review, library, edge cases). Keep them green.
- `swift run prompter-cli parse <file|-> [style]` — phrase + pause breakdown.
- `swift run prompter-cli follow <script> <audio>` — SpeechAnalyzer over a recording, matcher trace.

## Verifying without a screen recording permission

The shell can't `screencapture`. The app has debug flags that render to PNG and print a report:

- `Prompter --snapshot out.png` — the prompt panel + placement report (`out.png.txt`). Env: `PROMPTER_SNAPSHOT_THEME=light`, `PROMPTER_SNAPSHOT_HOVER=1`.
- `Prompter --snapshot-review out.png` — review card for a simulated session.
- `Prompter --snapshot-window library|settings|onboarding out.png` — unreliable for sidebars/segmented controls (offscreen capture artefacts); trust the panel captures, not these.
- `Prompter --follow-test recording.aiff` — **the real live pipeline** (AVAudioEngine → converter → SpeechAnalyzer → matcher → session → review) with a file as the mic and output muted. Run this after touching anything in `Sources/Prompter/Speech`.
- Make a test recording: `say -v Karen -r 165 -o spoken.aiff -f spoken.txt`.
- `Prompter --transcript` logs transcripts and phrase moves via NSLog (`log show --predicate 'process == "Prompter"'`).

Snapshot runs never persist preferences (`Preferences` suppresses writes when any `--snapshot*` flag is present).

## Design rules that matter

- Voice position and pace position are separate. The Pace Dot never moves the text.
- Phrase advances on the first matched word of the *next* phrase, so a deliberate pause keeps the current line highlighted.
- Matcher (`ScriptMatcher`) scores alignments only where they end at the latest spoken word; thresholds near 2.4 / far 4.0 / cold start 3.0. Both script and transcript go through `TextNormalizer.tokens(from:)`.
- Anything called from a realtime/background framework callback inside a `@MainActor` class must be written `{ @Sendable … in }` — see the audio tap in `SpeechService`.
- Persistence is Codable JSON (`ScriptLibrary`, `Preferences`). No SwiftData, no network.
- The prompt is a non-activating `NSPanel` at `.statusBar` level on all Spaces. Don't make it activate the app.
