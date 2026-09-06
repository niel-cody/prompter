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
- `Prompter --diagnose [out.txt]` — OS, hardware, every display's geometry and computed camera placement, mic access, speech model status, hot keys. Run this first on any unfamiliar Mac.

Debug flags bypass the single-instance guard, so they run while the app is open. Everything
else hands over to the running copy and exits.

## Shipping

`Scripts/release.sh <version>` bumps `Resources/Info.plist`, builds **universal**
(arm64 + x86_64), signs, zips, tags, pushes and publishes a GitHub release whose notes come
from that version's `## [x.y.z]` section in `CHANGELOG.md` — write those first. Users install
with `Scripts/install.sh` (served from `main` via raw.githubusercontent.com, which caches for
about five minutes after a push).

Builds are ad-hoc signed, so Gatekeeper rejects a browser-downloaded copy and right-click →
Open does **not** override that on macOS 15+. The installer clears `com.apple.quarantine`,
which is why it exists. Set `DEVELOPER_ID` and `NOTARY_PROFILE` once enrolled in the Apple
Developer Program and the problem goes away.

Snapshot runs never persist preferences (`Preferences` suppresses writes when any `--snapshot*` flag is present).

## Design rules that matter

- Voice position and pace position are separate. The Pace Dot never moves the text.
- Phrase advances on the first matched word of the *next* phrase, so a deliberate pause keeps the current line highlighted.
- Matcher (`ScriptMatcher`) scores alignments only where they end at the latest spoken word; thresholds near 2.4 / far 4.0 / cold start 3.0. Both script and transcript go through `TextNormalizer.tokens(from:)`.
- Anything called from a realtime/background framework callback inside a `@MainActor` class must be written `{ @Sendable … in }` — see the audio tap in `SpeechService`.
- Persistence is Codable JSON (`ScriptLibrary`, `Preferences`). No SwiftData, no network.
- The prompt is a non-activating `NSPanel` at `.statusBar` level on all Spaces. Don't make it activate the app.
- Camera/notch placement lives in `PrompterCore/PromptPlacement.swift` and is unit-tested against real MacBook notch geometry. Keep AppKit out of it; `CameraPlacement` is the only `NSScreen` bridge.
- `LSMinimumSystemVersion` is 26.0 because `SpeechAnalyzer` is macOS 26-only. Lowering it means writing an `SFSpeechRecognizer` fallback.
