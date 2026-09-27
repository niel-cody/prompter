# Backlog

The single list of what we are building, in the order we are building it. Claude reads this
first in every session; Niel and Claude edit it together. `docs/ARCHITECTURE.md` is the why,
`CHANGELOG.md` is the done.

## How this file works

- **Now** holds at most three items: what is being worked on right now. Nothing enters Now
  without leaving Next.
- **Next** is ordered, top first. Reprioritising is moving a line.
- **Later** is grouped by the phases in the architecture doc. Loosely ordered.
- **Inbox** is unordered. Every new idea goes here the moment it is said, even mid-task, with
  no sizing and no debate. Triage happens at the start of a session, not at capture time.
- One line per item: `P-nn` id, a verb phrase, size (S under an hour, M a session, L several),
  and a "so that" clause naming the outcome. The clause is what we reprioritise on.
- When an item ships it moves to `CHANGELOG.md` and its line is deleted here. Ids are never
  reused.
- Next free id: **P-39**.

## Now

- P-1 Verify the real system-audio tap on a live Zoom/Meet/Teams call (S) so that Call mode
  is proven on hardware, not just through recordings. Needs Niel: approve the System Audio
  Recording prompt, then check the footer says "hearing the call".
- P-2 First-run explanation of System Audio Recording inside the meeting detail (S) so that
  the permission prompt never surprises anyone and a refusal has a visible fix.

## Next

1. P-32 Sign with Developer ID and notarize releases (S once enrolled; needs Niel: join the
   Apple Developer Program, ~US$99/year, then set `DEVELOPER_ID` and `NOTARY_PROFILE`) so
   that beta testers download from the releases page and double-click, with no Terminal,
   and microphone permission survives updates. Decided 2026-09-27: direct download like
   Granola, not the Mac App Store (sandbox would block the system-audio tap, review would
   slow the update loop). Everything else about distribution is already in place.
2. P-4 Apple Foundation Models provider behind an `IntelligenceProvider` protocol, used for
   capture classification and sentiment (M) so that suggestions come from a model rather than
   cue lists, still on-device and free. Phase A.
3. P-5 `Suggestion` provenance on every model output, with accept/dismiss recorded (M) so
   that we have an audit trail and an eval set from day one. Phase A.
4. P-6 Versioned prompt files and `prompter-cli eval` over the `--meeting-test` fixtures with
   hand-labelled expected captures and speakers (M) so that model or prompt changes can't
   silently get worse. Phase A.
5. P-7 EventKit calendar: offer a meeting note when an event with a video link starts, with
   title, template and attendees pre-filled (M) so that speaker labelling has names to work
   with and nobody forgets to press Start. Phase A.
6. P-8 Speaker naming by model instead of regex, using surrounding turns and attendees (S
   once P-4 exists) so that "Priya" is recognised from more than "this is Priya". Phase A.
7. P-9 Wrap-up drafting by model per template section, Granola-style grey text (M) so that
   the write-up starts from the meeting rather than a blank box. Phase A.
8. P-10 Test Voice Follow and Meetings running at the same time on one mic (S) so that
   pitching from the prompt while capturing the room is known to work.
9. P-11 Diarization spike: FluidAudio (pyannote + WeSpeaker on CoreML) on the system channel
   (M) so that two remote voices with no verbal cues stop both being "Them".

## Later

### Phase B: backend

- P-12 Decide the five open questions in ARCHITECTURE.md §7 (host, sync scope, who pays for
  models, first platform for names, first work tracker) (S) so that Phase B can start.
- P-13 Workspaces, sign-in (Google and Microsoft OIDC), per-device tokens (L) so that a
  person's notes are theirs and only theirs.
- P-14 Sync engine: entity revisions, append-mostly merge, tombstones (L) so that the Mac
  stays local-first and offline while notes reach the backend.
- P-15 Sharing grants for meetings, capture sets and themes, with an audit log (M) so that
  feedback can be shared without the whole transcript.
- P-16 Claude provider via the backend for synthesis and chat, with privacy tiers enforced
  per meeting (M) so that tier-0 notes can never leave the Mac.

### Phase C: integrations

- P-17 Jira Product Discovery: send a capture as an Insight on an idea, idempotent through
  `ExternalRef` (M) so that customer feedback lands on the backlog where Oolio decides.
- P-18 Linear and Jira issues from Action captures, assignee from the resolved speaker (M).
- P-19 Slack summary post and Confluence page from the wrap-up (M).
- P-20 Zoom participant names and active speaker through Accessibility (M) so that Zoom
  calls get real names without a bot.
- P-21 Google Meet browser extension for the participant list and active speaker (L).
- P-22 Teams roster from Microsoft Graph to seed attendees (M).
- P-23 Detect which app owns the tapped audio (per-process tap) (S) so that the right
  platform adapter is chosen automatically.
- P-24 MCP server over the workspace and outbound webhooks (M) so that agents and the
  oolio-pm skills can work from the notes.

### Phase D: themes and encoders

- P-25 Embeddings per segment and capture, encoder-agnostic storage (M).
- P-26 Themes across meetings and per-customer views (L) so that "what have people said
  about X" has an answer.
- P-27 Second encoder provider (local or JEPA-style) behind the same protocol (M).

## Inbox

- P-28 Prep briefing before a meeting from calendar attendees and everything they said
  before (needs P-7 and P-26).
- P-29 The window snapshot tool renders sidebars blank; fine for now, fix if it starts
  costing time.
- P-33 Duolingo-grade first run: the magic moment (prompt follows your voice) inside the
  first minute, before any sign-up or settings, permissions asked one at a time only when
  the feature needs them (folds in P-2).
- P-34 Coming back: an engagement loop that fits event-driven work, not day-count streaks.
  Candidates: streak per meeting captured and wrapped up, weekly recap of meetings,
  captures and delivery score, and the calendar (P-7) as the thing that brings people back.
- P-35 Speaking-coach progression: delivery score, pace and filler-word trend over time as
  the honest place for Duolingo-style levels and progress.
- P-36 Write down the vision line in ARCHITECTURE.md: "Prompter prompts the human", it
  steers product people through what they say and what they hear, and is the gateway that
  pulls scripts and insights together and posts them to the right systems. Name stays.
- P-38 History by person: who I've worked with and talked to, across meetings, with
  commonalities and trends (the third sidebar section after Scripts and Meetings; builds
  on P-26 themes and per-customer views).
