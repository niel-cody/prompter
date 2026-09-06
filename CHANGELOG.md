# Changelog

All notable changes to Prompter. The most recent version is at the top; the section for a
version becomes its GitHub release notes.

## [Unreleased]

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
