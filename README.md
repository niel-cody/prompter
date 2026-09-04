# Prompter

A native macOS teleprompter that follows *you*. Prompter sits directly under your camera,
shows one phrase at a time, listens to what you actually say, and keeps your place while
you pause, ad-lib, repeat yourself or skip ahead. When you're done it tells you, briefly,
how the delivery went.

> I know what I want to say. I am looking straight at you. I am not rushing. I sound confident.

## The loop

1. Copy a script from anywhere.
2. Press **⌥⌘V**. The prompt appears under the camera (under the notch on a MacBook,
   top-centre on any other display).
3. Press **⌥⌘↩** and start talking. Spoken phrases fade, the current one stays crisp, the
   next one waits quietly below. A small **Pace Dot** moves under the current phrase at the
   pace you chose; stay level with it.
4. Press **⌥⌘.** (or run off the end) for the delivery review.

Everything runs on your Mac. Scripts are plain JSON files in `~/Library/Application
Support/Prompter/Scripts`. Speech recognition uses Apple's on-device `SpeechAnalyzer`;
microphone audio is never written anywhere. No account, no backend, no telemetry.

## Requirements

- macOS 26 (Tahoe) or later, Apple silicon.
- Xcode 26 or the matching Command Line Tools to build.

## Build & run

```bash
Scripts/build-app.sh debug --run      # builds and opens build/Prompter.app
swift test                            # PrompterCore unit tests
swift run prompter-cli parse script.txt professional    # see how a script is phrased and paced
swift run prompter-cli follow script.txt recording.aiff # replay a recording through Voice Follow
```

`say -o take.aiff -f script.txt` gives you a recording to test with when you don't want to
talk to your Mac.

Open `Package.swift` in Xcode to work on it there.

## Shortcuts

| Action | Shortcut |
|---|---|
| Prompt Clipboard | ⌥⌘V |
| Show / Hide prompt | ⌥⌘P |
| Start / Pause | ⌥⌘↩ |
| Previous / Next phrase | ⌥⌘← / ⌥⌘→ |
| Previous / Next paragraph | ⌥⌘↑ / ⌥⌘↓ |
| Smaller / Larger text | ⌥⌘− / ⌥⌘= |
| End session & review | ⌥⌘. |

After clicking the prompt, Space and the arrow keys work on their own without the modifiers.
The shortcuts work while Zoom, Teams, Chrome, Keynote or Loom have focus.

## How it works

```
Sources/PrompterCore        pure logic, fully unit-tested
  PhraseParser              script → sections → sentences → breath-sized phrases,
                            with pause kinds and emphasis inferred from structure
  Pacing / PacePlan         delivery styles → per-phrase ideal timing
  PaceConductor             where the Pace Dot is within the current phrase
  ScriptMatcher             recent transcript ↔ script alignment (Smith–Waterman over a
                            window around the last confirmed word) → phrase position
  DeliveryLog / Review      what happened → pace, pauses, rushed sections, score
  ScriptLibrary             JSON-per-script persistence

Sources/Prompter            the app
  Windows/PromptPanel       non-activating, status-bar-level NSPanel on every Space
  Windows/CameraPlacement   notch / top-centre placement per display
  Prompt/                   PromptSession (state + clock), PromptView, PaceDotView,
                            ClassicPromptView, PromptController
  Speech/                   SpeechService (AVAudioEngine → SpeechAnalyzer),
                            VoiceFollowController (transcript → matcher → session)
  Review/, Library/, Settings/, MenuBar/, Shortcuts/
```

Two ideas shape the design:

- **Voice position and pace position are separate.** Speech recognition decides where you
  are; the Pace Dot only shows where you'd ideally be. Rushing puts you ahead of the dot;
  a deliberate pause leaves it resting at the end of the phrase. It never moves the text.
- **Phrases, not words.** Scripts are split at punctuation, clause boundaries and a
  breath-length budget. Karaoke-style word chasing makes people read like robots; a phrase
  gives you room to say it your way.

## Delivery styles

| Style | Speaking rate | Feel |
|---|---|---|
| Measured | 135 wpm, longer pauses | Slow and deliberate |
| Professional (default) | 160 wpm | Calm boardroom pace, ≈120–130 wpm overall |
| Conversational | 175 wpm | Talking to a colleague |
| Energetic | 190 wpm, short pauses | Keeps a demo moving |

## Status

Working end to end on macOS 26: clipboard prompt, camera placement, phrase highlighting,
Pace Dot, Voice Follow with recovery, Classic and Manual modes, review, library, settings.
Not built, on purpose: accounts, sync, billing, recording, virtual camera, mobile.
