# Prompter platform architecture

Draft, 2026-09-26. Where the meeting-capture half of Prompter goes next: AI in the loop
without marrying a model, a backend that keeps people's notes apart but lets them share, and
integrations with the tools a product team already lives in. Nothing here changes what ships
today; it says how to grow it without a rewrite.

## 1. What stays true

- **Audio never leaves the device.** Recognition is on-device (`SpeechAnalyzer`). What
  syncs, shares or goes to a model is text: transcript, captures, notes. That is the privacy
  story and it is also what makes a backend cheap.
- **JSON is canonical, Markdown is a projection.** `MeetingNote` is the record. The Markdown
  mirror is rendered from it and never parsed back. Every downstream consumer (a script, an
  Obsidian vault, a model, an integration) keys off the same category headings and front
  matter, so they are a contract: change them deliberately.
- **AI output is a suggestion with provenance.** Captures already arrive as suggestions the
  user keeps or dismisses; speaker names arrive with a "?" until confirmed. Every future
  model output follows the same shape. The accept/dismiss signal is the eval set.
- **Models and integrations are adapters behind protocols.** Nothing in `PrompterCore`
  imports a vendor SDK.

## 2. Data model

The entities the backend, the sync engine and the integrations all agree on. Today's
`MeetingNote` maps onto this without loss; the new pieces are workspace, identity, sharing
and provenance.

| Entity | Purpose | Notes |
|---|---|---|
| `Workspace` | The tenant. A company, team or one person. | Every row carries `workspaceID`; isolation is enforced on it. |
| `User`, `Membership` | Who can sign in; which workspaces they belong to and with what role. | Roles: owner, member, guest. |
| `Person` | Someone who appears in meetings: a colleague, a customer. | Optional link to a `User`; optional link to a CRM/directory record. Attendees resolve to people. |
| `Meeting` | One session: title, template, mode (call / in person), times, owner, attendees, prep, notes, wrap-up. | Today's `MeetingNote` minus the arrays below. |
| `Segment` | A settled piece of transcript: time range, channel, text, speaker. | Append-only in practice. |
| `Speaker` | A label within a meeting ("Me", "Them", "Priya"), optionally resolved to a `Person`. | Confirmed or suggested, with the cue that suggested it. |
| `Capture` | A kept or suggested moment: category, text, time, sentiment, speaker, source, tags. | The unit of feedback. Shareable on its own. |
| `Suggestion` | Provenance for anything a model produced: job, provider, model, prompt version, input hash, output, accepted/dismissed. | Audit trail and eval data. See §3.4. |
| `Embedding` | A vector for a segment or capture: model, dimensions, vector. | Encoder-agnostic. See §3.5. |
| `Theme` | A cross-meeting grouping of captures (a recurring objection, a feature ask), human- or model-made. | The "categorise and use" stage. |
| `Template` | Prep prompts, wrap-up sections, tags; workspace-shareable. | Built-ins today. |
| `Share` | A grant: subject (user, team, workspace, link) × object (meeting, capture set, theme) × role (view, comment, edit). | See §4.3. |
| `ExternalRef` | A link from an entity to something elsewhere: calendar event, Zoom meeting id, Jira key, Linear issue, Slack thread. | How integrations stay idempotent. |

Rules that make offline-first work:

- IDs are client-generated UUIDs (v7, time-ordered). A meeting created on a plane is the
  same meeting when it syncs.
- Every entity has `rev`, `updatedAt`, `deletedAt` (tombstone). Nothing is hard-deleted
  until a retention job runs.
- New fields decode leniently with defaults, as the Swift models already do, so old clients
  and old files keep working.

## 3. AI in the loop

### 3.1 The jobs, in order of value

1. **Classify and score captures** as sentences settle. Replaces or ranks the rule-based
   `InsightDetector`. Needs to be cheap and fast (hundreds of calls a meeting), so this is
   the job for an on-device model first.
2. **Name speakers from context.** Replaces the regex heuristics in `SpeakerLabeler`
   ("this is Priya", "over to you, Sam") with a model that reads the surrounding turns and
   the attendees. Same output shape: a suggested label with a cue.
3. **Draft the wrap-up** per template section from kept captures and the transcript, in the
   Granola pattern: the user's words stay black, the model's additions are grey until kept.
4. **Cross-meeting synthesis.** Themes across sessions, what a customer has said over time,
   what changed since the last pitch. Needs retrieval (§3.5), not just prompting.
5. **Ask the notes** (chat over one meeting or a workspace).
6. **Prep briefing** before a meeting: calendar attendees × everything they said before.

### 3.2 Provider protocol

One protocol, many providers, chosen per job by policy. Sketch:

```swift
public enum IntelligenceJob: String { case classifyCapture, labelSpeaker, draftWrapUp, synthesise, chat, embed }

public protocol IntelligenceProvider: Sendable {
    var id: String { get }                           // "apple-foundation", "claude", "openai-compatible"
    var capabilities: Set<Capability> { get }        // .structuredOutput, .streaming, .embeddings, .longContext, .onDevice
    /// Structured request in, JSON-schema-validated output out. Prompts come from the job's
    /// versioned template, not from the caller.
    func run<Input: Encodable, Output: Decodable>(_ job: IntelligenceJob, input: Input, prompt: PromptTemplate,
                                                  output: Output.Type) async throws -> Output
    func embed(_ texts: [String]) async throws -> [Embedding]
}
```

Providers to build, in this order:

- **Apple Foundation Models** (`FoundationModels` framework, macOS 26). On-device, free,
  private, guided generation straight into Swift types. Right for jobs 1 and 2 and a
  first cut of 3. Limited context and reasoning; fine for per-sentence and per-section work.
- **Claude** (Anthropic Messages API, structured outputs). `claude-fable-5-1` for synthesis
  and chat, `claude-sonnet-5` or `claude-haiku-4-5` for bulk classification when cost matters.
  Through the backend (§4) so keys never sit on devices; direct with a BYO key as an option.
- **OpenAI-compatible endpoint.** One adapter covers OpenAI, Ollama, LM Studio and MLX
  servers, which is how a privacy-sensitive workspace runs a local model of its choosing.

### 3.3 Routing policy

```swift
struct ModelPolicy {
    var chain: [IntelligenceJob: [String]]   // e.g. classifyCapture: ["apple-foundation", "claude"]
    var privacyTier: PrivacyTier             // see below
    var costCeiling: Decimal?                // per workspace per month
    var latencyBudget: [IntelligenceJob: Duration]
}
```

A job walks its chain until a provider succeeds within budget. Default policy: on-device for
anything that runs during a meeting, cloud only for synthesis and chat, and only if the
workspace opted in.

Privacy tiers, set per workspace and stamped on every meeting:

| Tier | Where text may go |
|---|---|
| 0 | This Mac only. The default today and forever the default for a new install. |
| 1 | Prompter's backend and the model providers it contracts with. |
| 2 | A provider the user configured with their own key or endpoint. |

A tier-0 meeting never reaches a cloud provider, even if the policy later changes.

### 3.4 Prompts, evals, provenance

- Prompts are versioned files under `Resources/Prompts/<job>/<version>.md` with a JSON
  schema for the output. A job pins a version; bumping it is a reviewed change.
- Every model output is stored as a `Suggestion` with job, provider, model, prompt version,
  input hash and whether the user accepted it. That is the audit trail, the "why did it say
  that" answer, and the labelled data for the next model.
- The eval harness is the existing `--meeting-test` recordings plus hand-labelled expected
  captures and speakers. `prompter-cli eval` runs every provider over the fixtures and reports
  precision and recall per category, speaker accuracy and cost. A model or prompt change that
  drops a score doesn't ship.

### 3.5 Beyond today's LLMs

The parts of this tool that outlast any particular model are retrieval, clustering and
"what is new here". Design for encoders, not chat:

- Store embeddings per segment and capture, tagged with the model and dimensions, alongside
  the raw signal the text loses: timestamps, channel, pauses, sentiment, speaker, whether
  the capture was kept. A JEPA-style or audio-native encoder slots in as another `embed`
  provider without a schema change. (Assumption: "Jev" in the brief is JEPA, the joint
  embedding predictive architecture. If it meant something else, the principle holds.)
- Keep the data model free of prompt text and model-specific fields. Jobs consume entities;
  providers consume prompts.
- Themes (§2) are the human-visible result of clustering; they must survive re-embedding
  with a new model, so they reference captures, not vectors.

## 4. Storage, backend, tenancy, sharing

### 4.1 Local-first with sync

The Mac keeps the canonical JSON it keeps today and stays fully usable offline. A sync
engine pushes and pulls entity revisions:

- Segments and captures are append-mostly: set union, no conflicts in practice.
- Scalar fields (title, template, mode, speaker labels): last writer wins per field, by
  `updatedAt`, with the server as tiebreaker.
- Free text the user types (notes, wrap-up answers): three-way merge on the client against
  the last synced base; a CRDT (Automerge or Yjs through a small bridge) if concurrent
  editing of one note becomes a real use case. It isn't one yet.

### 4.2 Backend

Postgres with row-level security keyed on `workspaceID`, an HTTP+JSON API described in
OpenAPI, OIDC sign-in with Google and Microsoft (the people on Meet and Teams already have
those identities), per-device tokens. The API surface is ours (`PrompterAPI` protocol in the
app) so the hosting can change. Recommendation for the first version: Supabase, which is
Postgres, RLS, auth and realtime in one, and saves writing an auth service. Audio is never
uploaded; there is no audio bucket to secure.

Isolation, in order of strength:

1. `workspaceID` on every row and RLS policies that only ever see the caller's workspaces.
2. Meetings default to private to their owner inside the workspace.
3. Optional per-workspace encryption keys for text at rest (KMS-managed) for customers who
   ask; the on-device copy is already protected by FileVault.
4. Data residency by region at deploy time. Australia first if Oolio is the first tenant.

### 4.3 Sharing

Grants, not copies. A `Share` names a subject (user, team, workspace, or an expiring link),
an object and a role. The objects worth sharing separately:

- A **meeting**: transcript, captures, notes, wrap-up. Viewer, commenter or editor.
- A **capture set**: the feedback from a meeting without its transcript. This is the common
  product-team case: "here is what the customer said" without "here is everything we said".
- A **theme**: captures across meetings, with each capture still linking back to a meeting
  the reader may or may not be allowed to open.

Cross-workspace sharing is link-only and read-only. Every share and every read of a shared
object is in an audit log the workspace owner can see.

### 4.4 Schema sketch

```sql
create table workspaces (id uuid primary key, name text, privacy_tier smallint default 0, region text);
create table users (id uuid primary key, email text unique, name text);
create table memberships (workspace_id uuid references workspaces, user_id uuid references users, role text, primary key (workspace_id, user_id));
create table people (id uuid primary key, workspace_id uuid, name text, email text, user_id uuid null, external_ref jsonb);
create table meetings (id uuid primary key, workspace_id uuid, owner_id uuid, title text, template_id text, mode text,
    started_at timestamptz, ended_at timestamptz, attendees text, prep jsonb, notes text, wrap_up jsonb, tags text[],
    privacy_tier smallint, rev bigint, updated_at timestamptz, deleted_at timestamptz);
create table segments (id uuid primary key, meeting_id uuid, workspace_id uuid, start_s real, end_s real, channel text,
    text text, speaker text, speaker_suggested bool, rev bigint, updated_at timestamptz);
create table captures (id uuid primary key, meeting_id uuid, workspace_id uuid, category text, text text, at_s real,
    sentiment text, source text, kept bool, speaker text, tags text[], rev bigint, updated_at timestamptz, deleted_at timestamptz);
create table suggestions (id uuid primary key, workspace_id uuid, entity_type text, entity_id uuid, job text, provider text,
    model text, prompt_version text, input_hash text, output jsonb, accepted bool null, created_at timestamptz);
create table embeddings (entity_type text, entity_id uuid, workspace_id uuid, model text, dims int, vector vector, primary key (entity_type, entity_id, model));
create table themes (id uuid primary key, workspace_id uuid, title text, capture_ids uuid[], created_by text, updated_at timestamptz);
create table shares (id uuid primary key, workspace_id uuid, subject_type text, subject_id text, object_type text, object_id uuid, role text, expires_at timestamptz);
create table external_refs (entity_type text, entity_id uuid, system text, external_id text, url text, primary key (entity_type, entity_id, system));
-- RLS: every table has a policy `workspace_id in (select workspace_id from memberships where user_id = auth.uid())`,
-- and meetings/segments/captures add `or exists (select 1 from shares ...)`.
```

## 5. Integrations

One adapter protocol, several kinds. An integration declares what it can do; the app shows
only the actions the connected ones support.

```swift
public protocol Integration: Sendable {
    var id: String { get }                 // "google-calendar", "jira", "linear", "slack", "zoom", "google-meet", "teams"
    var kind: IntegrationKind { get }      // .calendar, .meetingPlatform, .workTracker, .knowledge, .chat
    var capabilities: Set<IntegrationCapability> { get }
    // .upcomingEvents, .participantNames, .activeSpeaker, .createIssue, .attachInsight, .createPage, .postSummary
}
```

### 5.1 Calendar (first, and the biggest win)

- **Locally, now:** EventKit reads the Mac's Calendar, which already syncs Google and
  Exchange accounts. When an event with a Zoom, Meet or Teams link is about to start,
  Prompter offers (or, if the user opts in, starts) a meeting note with the right template,
  the title, and the attendees pre-filled. Attendee names are what make speaker labelling
  work, so this alone raises the quality of every transcript.
- **Server side, later:** Google Calendar API and Microsoft Graph, so the backend can
  create meeting placeholders and match `ExternalRef`s without the Mac being awake.

### 5.2 Meeting platforms

The capture stays botless; the platforms add names.

- **Zoom (macOS):** read participant names and the active-speaker indicator from the Zoom
  window through Accessibility, which is how Granola shows display names on Zoom. Needs the
  Accessibility permission; degrades to "Them" without it.
- **Google Meet:** a small browser extension reads the participant list and the
  active-speaker highlight and posts them to the app over a local socket. Same as Granola's
  approach.
- **Teams:** no active-speaker signal without a bot. Microsoft Graph gives the roster and
  attendance report, which seeds the attendees; labelling then relies on the context
  heuristics and the user. Revisit when Graph exposes real-time media without a bot.
- **Which app is talking:** the process tap can list per-process audio, so the app can tell
  whether the tapped audio is Zoom, Teams or a browser tab and pick the right adapter.

### 5.3 Work trackers and knowledge tools

Captures map onto the tools cleanly because they already carry a category:

| Capture | Jira | Linear | Confluence / Notion | Slack |
|---|---|---|---|---|
| Action | Task, assignee from speaker if resolved to a person | Issue | | Reminder in a thread |
| Feedback, Insight, Objection, Quote | **JPD Insight** attached to an idea, with the quote and speaker as the evidence | Customer request / linked feedback | | |
| Decision | Comment on the linked epic or idea | Comment | Decision log page section | |
| Wrap-up | | | Page under the meeting's space | Summary post |

Each is a "Send to…" action on a capture or a meeting, idempotent through `ExternalRef`
(sending twice updates, never duplicates). Jira Product Discovery Insights are the natural
first target given how Oolio runs discovery.

### 5.4 Prompter as a source for other tools

- An **MCP server** over the workspace: list meetings, search captures, read a transcript,
  attach an insight. Any agent (Claude Code, the `oolio-pm` skills, a Slack bot) can then
  work from the notes without a bespoke integration.
- **Outbound webhooks** on meeting ended, capture kept, theme changed.
- **Export** stays Markdown; a folder sync to an Obsidian vault already exists.

## 6. Phasing

| Phase | Ships | Why this order |
|---|---|---|
| A. Local intelligence | Apple Foundation Models provider for capture classification, speaker naming and wrap-up drafts; `Suggestion` provenance; prompt files and `prompter-cli eval`; EventKit calendar with attendees pre-filled. | Big quality jump with no account, no backend, no cost, no privacy change. |
| B. Backend | Workspaces, sign-in, sync, sharing of meetings and capture sets; Claude provider via the backend for synthesis and chat; privacy tiers. | Sharing is the first thing a team asks for; synthesis needs data in one place. |
| C. Integrations | Jira / JPD Insights, Linear, Slack summaries, Confluence pages; Meet extension and Zoom names; MCP server and webhooks. | Names from platforms improve transcripts; work trackers close the loop from feedback to backlog. |
| D. Themes and encoders | Embeddings, themes across meetings, per-customer views, a second encoder provider (local or JEPA-style) behind the same protocol. | The "categorise and use" stage, built on everything above. |

## 7. Decisions to make

- Backend host: Supabase for speed, or an owned service for control. Region and residency.
- Whether transcripts sync by default or only captures and notes (a strong privacy default
  would be captures only, transcript on request).
- Who pays for cloud models: workspace plan, BYO key, or both.
- Which platform comes first for names: Zoom (Accessibility) is the least work; Meet needs
  an extension; Teams gives the least.
- Whether Jira Product Discovery Insights is the first work-tracker target.
