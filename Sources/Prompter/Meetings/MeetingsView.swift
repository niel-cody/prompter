import AppKit
import SwiftUI
import PrompterCore

/// New meeting notes from a template; the button itself starts Pitch feedback.
struct NewMeetingMenu: View {
    var meetings: MeetingController
    var prominent = false
    var create: (MeetingTemplate) -> Void

    var body: some View {
        Menu {
            ForEach(MeetingTemplate.builtIn) { template in
                Button {
                    create(template)
                } label: {
                    Text(template.name)
                    Text(template.summary)
                }
            }
        } label: {
            Label("New Meeting", systemImage: "plus")
        } primaryAction: {
            create(.pitchFeedback)
        }
        .if(prominent) { $0.buttonStyle(.borderedProminent) }
    }
}

/// A meeting in the sidebar: title, when, whether it's listening now.
struct MeetingRow: View {
    let note: MeetingNote
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled meeting" : note.title).lineLimit(1)
                HStack(spacing: 4) {
                    if isActive {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("Listening")
                    } else {
                        Text(note.startedAt ?? note.createdAt, format: .relative(presentation: .named))
                    }
                    let kept = note.keptCaptures.count
                    if kept > 0 { Text("· \(kept) kept") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

/// One meeting: your notes on the left, what the room said on the right.
struct MeetingDetailView: View {
    let note: MeetingNote
    var meetings: MeetingController

    private enum Pane: String, CaseIterable, Identifiable {
        case notes = "Notes", prep = "Prep", wrapUp = "Wrap-up"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .notes
    private var isActive: Bool { meetings.activeID == note.id }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // A plain HStack rather than HSplitView: a split view lets unwrapped transcript
            // text decide the pane's width and the pane runs off the window. The right pane
            // takes a fixed share of whatever width there is, so nothing is ever clipped.
            GeometryReader { geometry in
                let right = min(520, max(320, geometry.size.width * 0.42))
                HStack(spacing: 0) {
                    leftPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    rightPane
                        .frame(width: right)
                        .frame(maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    meetings.markInsight()
                } label: {
                    Label("Mark Insight", systemImage: "lightbulb.max")
                }
                .help("Keep the last 20 seconds of what was said (⌥⌘I)")
                .disabled(!isActive)

                Menu {
                    Button("Copy Markdown") { meetings.copyMarkdown(note.id) }
                    Button("Export Markdown…") { meetings.exportMarkdown(note.id) }
                    Button("Reveal in Finder") { meetings.revealMarkdown(note.id) }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    meetings.toggleCapture(note.id)
                } label: {
                    Label(isActive ? "Stop" : (note.isEnded ? "Resume" : "Start Listening"),
                          systemImage: isActive ? "stop.fill" : "mic.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .red : .accentColor)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: binding(\.title))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
            HStack(spacing: 10) {
                if let template = note.template {
                    Label(template.name, systemImage: "doc.text")
                }
                Text(note.startedAt ?? note.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                if let duration = note.duration, note.isEnded, !isActive {
                    Text(MeetingMarkdown.clock(duration))
                }
                let mood = note.overallSentiment
                if mood != .neutral {
                    Label(mood.displayName, systemImage: SentimentStyle.symbol(mood)).foregroundStyle(SentimentStyle.color(mood))
                }
                Spacer()
            }
            .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Picker("", selection: Binding(get: { note.isInPerson }, set: { meetings.setInPerson($0, for: note.id) })) {
                    Text("Call").tag(false)
                    Text("In person").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("On a call, the microphone is you and system audio is everyone else. In person, the microphone hears the whole room.")
                TextField(note.isInPerson ? "Who's in the room" : "Who's on the call (names help label speakers)", text: binding(\.attendees))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 150, maxWidth: 320)
                if let library = meetings.library, !library.documents.isEmpty {
                    Picker("Script", selection: Binding(get: { note.scriptID }, set: { id in meetings.modify(note.id) { $0.scriptID = id } })) {
                        Text("No script").tag(UUID?.none)
                        ForEach(library.documents) { doc in Text(doc.title).tag(UUID?.some(doc.id)) }
                    }
                    .frame(minWidth: 140, maxWidth: 260)
                    .help("The script you're pitching. Its vocabulary helps recognition.")
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var leftPane: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            switch pane {
            case .notes:
                TextEditor(text: binding(\.notes))
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .overlay(alignment: .topLeading) {
                        if note.notes.isEmpty {
                            Text("Your notes. What you saw, not what was said; the transcript has that.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 21).padding(.top, 1)
                                .allowsHitTesting(false)
                        }
                    }
            case .prep:
                FieldsEditor(fields: binding(\.prep), emptyHint: "This template has no prep prompts.")
            case .wrapUp:
                VStack(spacing: 0) {
                    HStack {
                        Text("Written after. Start from what was captured, then edit.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Draft from Captures") { meetings.draftWrapUp(note.id) }
                            .disabled(note.keptCaptures.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    FieldsEditor(fields: binding(\.wrapUp), emptyHint: "This template has no wrap-up sections.")
                }
            }
        }
    }

    private var rightPane: some View {
        VSplitView {
            CapturesPane(note: note, meetings: meetings)
                .frame(minHeight: 200, idealHeight: 320, maxHeight: .infinity)
            TranscriptPane(note: note, liveText: isActive ? meetings.liveText : [:], meetings: meetings)
                .frame(minHeight: 120, idealHeight: 200, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            statusLabel
            if let system = meetings.systemAudioStatus {
                Text("·")
                if meetings.systemAudioMayBeBlocked {
                    Text(system)
                    Button("Allow System Audio Recording…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                } else {
                    Text(system)
                }
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if isActive {
            switch meetings.speech.state {
            case .listening:
                Label("Listening · \(MeetingMarkdown.clock(meetings.elapsed))", systemImage: "waveform").foregroundStyle(.red)
            case .requestingPermission:
                Text("Waiting for microphone permission…")
            case .preparing:
                Text("Preparing speech recognition…")
            case .downloadingModel(let fraction):
                Text("Downloading speech model… \(Int(fraction * 100))%")
            case .denied:
                HStack {
                    Text("Microphone access is denied.")
                    Button("Open Privacy Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            case .unavailable(let message):
                Text(message)
            case .idle:
                Text("Starting…")
            }
        } else if note.isEnded {
            Text("\(note.transcript.count) transcript segments · \(note.speakers.count) speakers · \(note.keptCaptures.count) kept · \(note.suggestedCaptures.count) suggested")
        } else if note.isInPerson {
            Text("Press Start Listening when the meeting begins. The microphone hears the room; everything stays on this Mac.")
        } else {
            Text("Press Start Listening when the call begins. You come from the microphone, everyone else from what the Mac is playing. Nothing joins the call.")
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<MeetingNote, T>) -> Binding<T> {
        Binding(get: { note[keyPath: keyPath] }, set: { value in meetings.modify(note.id) { $0[keyPath: keyPath] = value } })
    }
}

/// Prompt-and-answer fields for prep and wrap-up.
private struct FieldsEditor: View {
    @Binding var fields: [TemplateField]
    var emptyHint: String

    var body: some View {
        if fields.isEmpty {
            Text(emptyHint).foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach($fields) { $field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.prompt).font(.system(size: 13, weight: .semibold))
                            TextEditor(text: $field.answer)
                                .font(.system(size: 14))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 72)
                                .padding(6)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}

// MARK: - Captures

private struct CapturesPane: View {
    let note: MeetingNote
    var meetings: MeetingController
    @State private var newText = ""
    @State private var newCategory: CaptureCategory = .feedback

    private var ordered: [Capture] { note.captures.sorted { $0.at < $1.at } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Captures").font(.system(size: 13, weight: .semibold))
                Text("\(note.keptCaptures.count) kept · \(note.suggestedCaptures.count) suggested")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !note.suggestedCaptures.isEmpty {
                    Button("Keep All") { meetings.keepAllSuggestions(in: note.id) }.controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            if ordered.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "lightbulb").font(.title2).foregroundStyle(.tertiary)
                    Text("Nothing captured yet.").foregroundStyle(.secondary)
                    Text("Suggestions appear here as feedback, objections, questions and decisions are said. Press ⌥⌘I to keep the last 20 seconds yourself.")
                        .font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(ordered) { capture in
                            CaptureRow(capture: capture, noteID: note.id, meetings: meetings).id(capture.id)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: ordered.count) { _, _ in
                        if let last = ordered.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Picker("", selection: $newCategory) {
                    ForEach(CaptureCategory.allCases) { Label($0.displayName, systemImage: $0.symbolName).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
                TextField("Add something you heard or noticed…", text: $newText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        meetings.addCapture(to: note.id, text: newText, category: newCategory)
                        newText = ""
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct CaptureRow: View {
    let capture: Capture
    let noteID: UUID
    var meetings: MeetingController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: capture.category.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(capture.isKept ? SentimentStyle.color(capture.sentiment) : .secondary)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(capture.text)
                    .font(.system(size: 13))
                    .foregroundStyle(capture.isKept ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    // Tokens never break mid-word; when the pane is narrow the less
                    // important ones go rather than hyphenate.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { meta(full: true) }
                        HStack(spacing: 8) { meta(full: false) }
                    }
                    if !capture.isKept {
                        Spacer(minLength: 4)
                        Button("Keep") { meetings.keep(capture.id, in: noteID) }
                        Button("Dismiss") { meetings.remove(capture.id, from: noteID) }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Menu("Category") {
                ForEach(CaptureCategory.allCases) { category in
                    Button {
                        meetings.setCategory(category, for: capture.id, in: noteID)
                    } label: {
                        Label(category.displayName, systemImage: category.symbolName)
                    }
                }
            }
            Menu("Sentiment") {
                ForEach(Sentiment.allCases, id: \.self) { s in
                    Button(s.displayName) { meetings.setSentiment(s, for: capture.id, in: noteID) }
                }
            }
            if !capture.isKept { Button("Keep") { meetings.keep(capture.id, in: noteID) } }
            Divider()
            Button("Delete", role: .destructive) { meetings.remove(capture.id, from: noteID) }
        }
    }
}

private extension CaptureRow {
    @ViewBuilder func meta(full: Bool) -> some View {
        Text(MeetingMarkdown.clock(capture.at)).monospacedDigit().fixedSize()
        if let speaker = capture.speaker { Text(speaker).fontWeight(.medium).lineLimit(1).fixedSize() }
        Text(capture.category.displayName).fixedSize()
        if full {
            if capture.sentiment != .neutral { Text(capture.sentiment.displayName).fixedSize() }
            if capture.source == .marked { Text("marked").fixedSize() }
            if !capture.isKept { Text("suggested").italic().fixedSize() }
        }
    }
}

// MARK: - Transcript

private struct TranscriptPane: View {
    let note: MeetingNote
    let liveText: [AudioChannel: String]
    var meetings: MeetingController

    /// Lines grouped into turns: consecutive segments by the same speaker.
    private var turns: [(id: UUID, speaker: String, suggested: Bool, channel: AudioChannel, segments: [TranscriptSegment])] {
        var out: [(id: UUID, speaker: String, suggested: Bool, channel: AudioChannel, segments: [TranscriptSegment])] = []
        for segment in note.transcript {
            let label = note.speakerLabel(of: segment)
            if let last = out.indices.last, out[last].speaker == label, out[last].channel == segment.channel {
                out[last].segments.append(segment)
                out[last].suggested = out[last].suggested || segment.speakerIsSuggested
            } else {
                out.append((id: segment.id, speaker: label, suggested: segment.speakerIsSuggested, channel: segment.channel, segments: [segment]))
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transcript").font(.system(size: 13, weight: .semibold))
                if !note.speakers.isEmpty {
                    Text(note.speakers.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            if note.transcript.isEmpty && liveText.isEmpty {
                Text(note.isInPerson ? "The transcript builds here as people speak."
                                     : "The transcript builds here. You come from the microphone; the other side of the call from system audio.")
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(turns, id: \.id) { turn in
                                VStack(alignment: .leading, spacing: 3) {
                                    SpeakerLabel(turn: turn, note: note, meetings: meetings)
                                    ForEach(turn.segments) { segment in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(MeetingMarkdown.clock(segment.start))
                                                .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                                                .padding(.top, 2)
                                            Text(segment.text).font(.system(size: 13))
                                                .textSelection(.enabled)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .id(segment.id)
                                        .contextMenu { lineMenu(for: segment) }
                                    }
                                }
                            }
                            ForEach(AudioChannel.allCases, id: \.self) { channel in
                                if let live = liveText[channel], !live.isEmpty {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(note.defaultSpeaker(for: channel)).font(.caption).foregroundStyle(.tertiary).padding(.top, 2)
                                        Text(live).font(.system(size: 13)).italic().foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .id("live-\(channel.rawValue)")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: note.transcript.count) { _, _ in
                        withAnimation {
                            if let channel = AudioChannel.allCases.last(where: { !(liveText[$0] ?? "").isEmpty }) {
                                proxy.scrollTo("live-\(channel.rawValue)", anchor: .bottom)
                            } else if let last = note.transcript.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: liveText) { _, text in
                        if let channel = AudioChannel.allCases.last(where: { !(text[$0] ?? "").isEmpty }) {
                            proxy.scrollTo("live-\(channel.rawValue)", anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lineMenu(for segment: TranscriptSegment) -> some View {
        Menu("This line was said by") {
            ForEach(speakerChoices(for: segment.channel), id: \.self) { name in
                Button(name) { meetings.setSpeaker(name, for: segment.id, in: note.id) }
            }
        }
    }

    private func speakerChoices(for channel: AudioChannel) -> [String] {
        var out = [note.defaultSpeaker(for: channel)]
        for name in note.attendeeNames + note.speakers where !out.contains(name) { out.append(name) }
        return out
    }
}

/// The name above a turn. Click it to accept a suggestion, rename everyone with that label,
/// or pick someone from the attendees.
private struct SpeakerLabel: View {
    let turn: (id: UUID, speaker: String, suggested: Bool, channel: AudioChannel, segments: [TranscriptSegment])
    let note: MeetingNote
    var meetings: MeetingController
    @State private var renaming = false
    @State private var newName = ""

    private var isDefault: Bool { turn.speaker == note.defaultSpeaker(for: turn.channel) }

    var body: some View {
        Menu {
            if turn.suggested {
                Button("Confirm \(turn.speaker)") { meetings.confirmSpeaker(turn.speaker, in: note.id) }
                Divider()
            }
            Section("Everything labelled \(turn.speaker) was") {
                ForEach(choices, id: \.self) { name in
                    Button(name) { meetings.relabelSpeaker(turn.speaker, to: name, in: note.id) }
                }
                Button("Someone else…") { newName = ""; renaming = true }
            }
            Section("Just this turn was") {
                ForEach(choices, id: \.self) { name in
                    Button(name) { for s in turn.segments { meetings.setSpeaker(name, for: s.id, in: note.id) } }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(turn.speaker).font(.system(size: 12, weight: .semibold))
                if turn.suggested { Text("?").font(.system(size: 12)).foregroundStyle(.secondary) }
            }
            .foregroundStyle(isDefault ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(turn.suggested ? "Suggested from context. Click to confirm or change." : "Click to change who said this.")
        .popover(isPresented: $renaming) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rename \(turn.speaker)").font(.headline)
                TextField("Name", text: $newName)
                    .frame(width: 200)
                    .onSubmit { commitRename() }
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = false }
                    Button("Rename") { commitRename() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }

    private func commitRename() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        meetings.relabelSpeaker(turn.speaker, to: name, in: note.id)
        renaming = false
    }

    private var choices: [String] {
        var out = [note.defaultSpeaker(for: turn.channel)]
        for name in note.attendeeNames + note.speakers where !out.contains(name) && name != turn.speaker { out.append(name) }
        return out
    }

    private var color: Color {
        if isDefault { return turn.channel == .microphone ? .accentColor : .secondary }
        let palette: [Color] = [.blue, .purple, .teal, .pink, .indigo, .mint, .brown, .cyan]
        let hash = turn.speaker.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return palette[hash % palette.count]
    }
}

enum SentimentStyle {
    static func color(_ s: Sentiment) -> Color {
        switch s {
        case .positive: .green
        case .negative: .orange
        case .mixed: .yellow
        case .neutral: .accentColor
        }
    }

    static func symbol(_ s: Sentiment) -> String {
        switch s {
        case .positive: "face.smiling"
        case .negative: "face.dashed"
        case .mixed: "face.smiling.inverse"
        case .neutral: "minus.circle"
        }
    }
}

private extension View {
    @ViewBuilder
    func `if`<T: View>(_ condition: Bool, transform: (Self) -> T) -> some View {
        if condition { transform(self) } else { self }
    }
}
