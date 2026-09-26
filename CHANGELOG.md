# Changelog

All notable changes to Prompter. The most recent version is at the top; the section for a
version becomes its GitHub release notes.

## [Unreleased]

## [0.10.0] — 2026-09-26

Prompter grows a second half. Prompting helps you say the thing clearly; Meetings captures
what the room says back.

- **Meetings**: a botless meeting note taker in the spirit of Granola. Nothing joins the
  call. Start a note before you pitch and Prompter listens on two channels: the microphone
  (you) and what the Mac is playing (everyone else on the call), each through its own
  on-device recogniser. Menu bar → New Meeting Notes, or ⌘M for the Meetings window.
- **Who said what**: transcript lines are labelled "Me" or "Them" by channel. Names are
  suggested from context, when someone introduces themself ("this is Priya"), when you
  address them ("Priya, what do you think?") and while the same person keeps talking, and
  marked with a "?" until you confirm. Click a name to confirm it, rename everyone with
  that label, or fix just one turn. Names in the attendees field help.
- System audio uses a Core Audio process tap: macOS asks once for "System Audio Recording"
  and nothing is installed. The microphone runs with echo cancellation on a call so the
  other side isn't transcribed twice. An "In person" switch uses the mic for the whole room.
- **Captures**: as people speak, feedback, objections, questions, decisions, actions,
  insights and anything said with feeling are flagged as suggestions with a sentiment.
  Keep, recategorise or dismiss them. ⌥⌘I keeps the last 20 seconds yourself; you can also
  type a capture. Detection is rule-based and runs entirely on the Mac.
- **Templates**: Pitch feedback, Customer discovery, Stakeholder review and Blank, each with
  prep prompts to answer beforehand and wrap-up sections to write afterwards. "Draft from
  Captures" seeds the wrap-up from what was kept.
- **Markdown**: every meeting is saved as JSON in Application Support and mirrored as a
  Markdown file with YAML front matter (template, tags, sentiment, capture counts) and one
  heading per category, so the notes can be grepped, categorised and fed to other tools.
  Settings → Meetings points the mirror at any folder, such as an Obsidian vault.
- A meeting can be tied to the script being pitched; its vocabulary biases recognition.
- `Prompter --meeting-test mic.aiff [system.aiff]` runs recordings through the live
  capture pipeline (two files simulate a call) and prints the Markdown;
  `prompter-cli insights transcript.txt` traces the detector sentence by sentence.
- `docs/ARCHITECTURE.md` sketches where this goes next: swappable AI providers, a backend
  with sharing, and integrations with calendars, meeting platforms and work trackers.
  `docs/BACKLOG.md` is the ordered list of what comes next.

Known at release: the system-audio tap has been exercised through recordings, not yet on a
live call. Start a Meeting in Call mode during a real call, approve "System Audio
Recording" when asked, and the footer should say "hearing the call".

## [0.9.2] — 2026-09-05

- Only one Prompter runs at a time. A second copy now hands over to the one already
  running instead of adding a duplicate menu-bar icon and competing for the same shortcuts.
- The installer quits a running copy before replacing it, so upgrading in place works.
- Update checking (release parsing, version comparison) moved into tested code.

## [0.9.1] — 2026-09-05

Ready to install and demo on a second Mac.

- Universal build: Prompter now runs natively on Apple silicon and on Intel Macs.
- One-line installer that fetches the release and clears the quarantine flag, so the app
  opens without a Gatekeeper detour.
- The prompt now says "Downloading speech model…" with progress the first time Voice Follow
  runs on a Mac, instead of appearing to hang on "Preparing…".
- Camera and notch placement moved into tested code, including MacBook notch geometry,
  external displays, displays that aren't at the origin, and auto-hidden menu bars.
- A remembered prompt position is only restored if it still fits the display it's on.
- `Prompter --diagnose` prints OS, hardware, displays, camera placement, microphone and
  speech-model status: run it on any Mac you plan to present from.

## [0.9.0] — 2026-09-05

First shareable build.

- Clipboard Prompt: copy text, press ⌥⌘V, the prompt appears under your camera.
- Coach mode: phrase-by-phrase prompting with the Pace Dot and suggested pauses.
- Voice Follow: on-device speech recognition keeps your place while you pause, ad-lib,
  repeat yourself or skip ahead. Audio never leaves your Mac.
- Delivery review at the end of a session: pace, rushed stretches, pauses taken, a score.
- Delivery styles: Measured, Professional (default), Conversational, Energetic.
- Classic scrolling and Manual modes.
- Script library with autosave, search, favourites, word count and estimated duration.
- Menu-bar app with global shortcuts that work over Zoom, Teams, Chrome and Keynote.
- Multi-display aware; remembers the prompt's position per display.

**Installing:** see the README. Prompter isn't notarized by Apple yet, so a build downloaded
through a browser is blocked by Gatekeeper; the installer avoids that. Requires macOS 26.
