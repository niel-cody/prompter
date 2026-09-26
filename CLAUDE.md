# Prompter — notes for Claude

Native macOS 26 teleprompter + speaking coach, plus Meetings: botless capture of what the
room says back. Swift 6 / SwiftUI / AppKit, SwiftPM only (no .xcodeproj). Open
`Package.swift` in Xcode if you want the IDE.

## Working with Niel (spelled N-I-E-L)

- **Read `docs/BACKLOG.md` first, every session.** It is the one list of what we are building
  and in what order. `docs/ARCHITECTURE.md` is the why; `CHANGELOG.md` is the done.
- Start a session by triaging the backlog's Inbox into Next or Later and confirming the top
  of Next with Niel in one line. Work from Now (max three items). When an item ships, move
  it to the changelog and delete its line.
- **Capture ideas immediately.** When Niel mentions something new, even mid-task, add a line
  to Inbox (next free `P-nn` id, bump the counter) and carry on. Don't size or debate it at
  capture time.
- **Keep Niel on track.** He asked for this. If the conversation drifts from Now and Next
  without a decision to reprioritise, say plainly: "Hi Niel, this is the way we're meant to be
  working", point at the backlog, and offer to Inbox the new thing or move it into Now. If
  he says move it, move it; the diff records the decision. Focus is the job: a great product
  comes from finishing things in order.
- Reprioritising is editing the file, nothing else. Never keep a parallel list in chat.

## Build, test, run

- `Scripts/build-app.sh debug [--run]` — builds and assembles `build/Prompter.app` (ad-hoc signed). Always launch the *bundle*, not the bare binary, when microphone/speech permission matters.
- `swift test` — PrompterCore unit tests (parser, pacing, matcher, review, library, edge cases). Keep them green.
- `swift run prompter-cli parse <file|-> [style]` — phrase + pause breakdown.
- `swift run prompter-cli follow <script> <audio>` — SpeechAnalyzer over a recording, matcher trace.
- `swift run prompter-cli insights <transcript|->` — what `InsightDetector` flags per sentence and which cue fired.

## Verifying without a screen recording permission

The shell can't `screencapture`. The app has debug flags that render to PNG and print a report:

- `Prompter --snapshot out.png` — the prompt panel + placement report (`out.png.txt`). Env: `PROMPTER_SNAPSHOT_THEME=light`, `PROMPTER_SNAPSHOT_HOVER=1`.
- `Prompter --snapshot-review out.png` — review card for a simulated session.
- `Prompter --snapshot-window library|settings|onboarding out.png` — unreliable for sidebars/segmented controls (offscreen capture artefacts); trust the panel captures, not these.
- `Prompter --follow-test recording.aiff` — **the real live pipeline** (AVAudioEngine → converter → SpeechAnalyzer → matcher → session → review) with a file as the mic and output muted. Run this after touching anything in `Sources/Prompter/Speech`.
- `Prompter --meeting-test mic.aiff [system.aiff]` — the same pipeline into meeting capture (transcript → `SpeakerLabeler` → `InsightDetector` → Markdown) using a throwaway store; two files simulate a call (mic = Me, second file = system audio = Them). Prints labelled segments, suggestions and the final Markdown. Run this after touching `Sources/Prompter/Meetings`, `Speech`, the labeler or the detector. `say` supports `[[slnc 5000]]` for silences, which is how to stage turn-taking between the two files.
- The real system-audio tap (`SystemAudioTap`) can't be driven from a file. It needs "System Audio Recording" (Privacy & Security → Screen & System Audio Recording); a refusal yields silence, not an error, so the footer watches `systemAudioPeak`.
- Make a test recording: `say -v Karen -r 165 -o spoken.aiff -f spoken.txt`.
- `Prompter --transcript` logs transcripts and phrase moves via NSLog (`log show --predicate 'process == "Prompter"'`).
- `Prompter --diagnose [out.txt]` — OS, hardware, every display's geometry and computed camera placement, mic access, speech model status, hot keys. Run this first on any unfamiliar Mac.
- `Prompter --update-test <zip> [target.app]` — the file-system half of an in-app update (unpack → verify → swap) against a scratch copy of the app; reports each step and checks for leftovers. `Prompter --update-live`, run **from a scratch copy whose Info.plist says an older version**, does the real thing against the real GitHub release and stops short of relaunching. `Prompter --snapshot-update out.png` renders the update window in every state (`out-<state>.png` for layout, `out-<state>-text.png` for the words). Run these after touching `Sources/Prompter/Updates`.

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

Beta feedback: menu bar → Send Feedback… (`FeedbackComposer`) opens a mail to the address
in that file with `Diagnostics.summary()` appended. Change the address there if it moves.

After the first install, updates happen inside the app (`Sources/Prompter/Updates`):
`UpdateChecker` is the state machine and window owner, `UpdateInstaller` downloads, unpacks,
verifies (bundle identity, `codesign --verify`, the release's `.sha256`) and swaps the bundle
with two renames in its own folder, then relaunches once the old process has exited. If the
folder isn't writable it runs the swap once with administrator privileges. `release.sh`
publishes the `.sha256` asset; keep doing so, the updater refuses a mismatch. Copies older
than 0.11.0 only know how to open the releases page, so the move onto in-app updates is one
last manual install.

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

## Meetings (the capture half)

- Prompter is one component of a product-person's toolkit: prompting helps you say it; Meetings (`Sources/Prompter/Meetings`, models in `PrompterCore/Meeting*.swift`) captures what the room says back. Botless, Granola-style: two `SpeechService` instances, one on the microphone (`.microphone(echoCancelled: true)` on a call, so the speakers aren't heard twice) and one on `.systemAudio` (a Core Audio process tap in `SystemAudioTap`). Channel decides "Me" vs "Them"; `isInPerson` collapses to one mic channel labelled "Room".
- Speaker names are heuristics in `SpeakerLabeler` (introductions, being addressed by a known name, continuity within 3 s) and always land as `speakerIsSuggested == true`. Apple's `SpeechAnalyzer` has no diarization; two remote voices with no cues both stay "Them". Relabeling (`setSpeaker`, `relabel`, `confirmSpeaker`) lives on `MeetingNote` and flows into captures.
- `InsightDetector.detect(_:from:inPerson:)` only flags decisions and actions from the presenter's own channel on a call; everything counts in person.
- New model fields must decode leniently (`decodeIfPresent` with defaults) so older JSON in the user's library keeps loading; see the custom `init(from:)`s.
- `InsightDetector` is deliberately rule-based (cue phrases on `TextNormalizer` tokens, lexicon sentiment with negation). Detections are *suggestions* (`Capture.isKept == false`) until the user keeps them. Category order matters: decision > action > objection > question > feedback > insight > sentiment catch-all.
- Sentences can straddle two settled transcript results; `MeetingController` buffers the tail until a terminator arrives and flushes it on stop.
- `MeetingStore` keeps JSON as the source of truth and mirrors every save to Markdown (`MeetingMarkdown`). The front matter keys and the `### <Category>` headings are the contract for anything downstream; don't rename them casually. The mirror folder is a preference (`meetingNotesDirectory`).
- Next stages the user has in mind: categorising and using the captured notes across sessions, AI providers that can be swapped as models change, a backend with per-user isolation and sharing, and integrations (calendar, Teams/Meet/Zoom, Jira/Linear). The design is in `docs/ARCHITECTURE.md`; build on the JSON/Markdown contract, not around it.
