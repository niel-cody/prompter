import AppKit
import Foundation
import Observation
import PrompterCore

/// Meeting capture: two on-device recognisers, one on the microphone (you) and one on
/// system audio (everyone on the call), a timestamped transcript labelled by who said what,
/// suggestions for things worth keeping as they are said, and JSON plus a Markdown mirror.
/// No bot joins anything; the Mac listens to the call it is already on, the way Granola does.
@MainActor
@Observable
final class MeetingController {
    /// The microphone: the person at the Mac, or the whole room in person.
    let speech = SpeechService()
    /// What the Mac is playing: the remote participants.
    let systemSpeech = SpeechService()
    private let store: MeetingStore
    private(set) var notes: [MeetingNote] = []
    var selectedID: UUID?
    var searchText = "" {
        didSet { refresh() }
    }
    /// The note currently being captured, if any.
    private(set) var activeID: UUID?
    /// Volatile transcript per channel for the stretch being recognised right now.
    private(set) var liveText: [AudioChannel: String] = [:]
    /// Seconds since the active note started; ticks once a second while capturing.
    private(set) var elapsed: TimeInterval = 0
    /// Scripts in the library, so a meeting can be tied to the script being pitched.
    var library: LibraryModel?
    /// Debug: recordings standing in for the microphone and for system audio.
    var testFiles: (microphone: URL, system: URL?)?

    /// Mark Insight keeps this much of the most recent transcript.
    static let markWindow: TimeInterval = 20

    private let detector = InsightDetector()
    private let labeler = SpeakerLabeler()
    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private var clock: Task<Void, Never>?
    private var startedAt: Date?
    /// Recognised text per channel waiting for a sentence terminator before the detector sees it.
    private var pending: [AudioChannel: (text: String, start: TimeInterval)] = [:]
    private var latestTime: TimeInterval = 0

    init(store: MeetingStore) {
        self.store = store
        refresh()
        speech.onTranscript = { [weak self] update in self?.handle(update, on: .microphone) }
        systemSpeech.onTranscript = { [weak self] update in self?.handle(update, on: .system) }
    }

    var selected: MeetingNote? { selectedID.flatMap { id in notes.first { $0.id == id } } }
    var active: MeetingNote? { activeID.flatMap { id in notes.first { $0.id == id } } }
    var isCapturing: Bool { activeID != nil }
    var markdownDirectory: URL { store.markdownDirectory }

    func note(id: UUID) -> MeetingNote? { notes.first { $0.id == id } ?? store.note(id: id) }

    func refresh() {
        // Keep in-memory edits that haven't hit disk yet.
        let unsaved = Dictionary(uniqueKeysWithValues: notes.filter { saveTasks[$0.id] != nil }.map { ($0.id, $0) })
        notes = store.search(searchText).map { unsaved[$0.id] ?? $0 }
    }

    // MARK: - Creating and editing

    @discardableResult
    func create(template: MeetingTemplate, title: String = "") -> MeetingNote {
        let name = title.isEmpty ? Self.defaultTitle(for: template) : title
        let note = MeetingNote(title: name, template: template)
        let saved = (try? store.save(note)) ?? note
        refresh()
        selectedID = saved.id
        return saved
    }

    static func defaultTitle(for template: MeetingTemplate) -> String {
        let day = Date().formatted(.dateTime.day().month(.abbreviated))
        return "\(template.name), \(day)"
    }

    /// Apply a change in memory now and write it to disk shortly after.
    func modify(_ id: UUID, _ change: (inout MeetingNote) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else {
            if var stored = store.note(id: id) {
                change(&stored)
                _ = try? store.save(stored)
                refresh()
            }
            return
        }
        change(&notes[i])
        scheduleSave(notes[i])
    }

    private func scheduleSave(_ note: MeetingNote) {
        saveTasks[note.id]?.cancel()
        saveTasks[note.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow(note.id)
        }
    }

    private func saveNow(_ id: UUID) {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        guard let note = notes.first(where: { $0.id == id }) else { return }
        _ = try? store.save(note)
        refresh()
    }

    func delete(_ id: UUID) {
        if activeID == id { stop() }
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        _ = try? store.delete(id: id)
        if selectedID == id { selectedID = nil }
        refresh()
    }

    // MARK: - Capturing

    func start(_ id: UUID) {
        if let activeID, activeID != id { stop() }
        guard activeID == nil, let note = note(id: id) else { return }
        if !notes.contains(where: { $0.id == id }) { searchText = "" }
        activeID = id
        selectedID = id
        let startedAt = note.startedAt ?? Date()
        self.startedAt = startedAt
        modify(id) {
            $0.startedAt = startedAt
            $0.endedAt = nil
        }
        pending = [:]
        liveText = [:]
        latestTime = Date().timeIntervalSince(startedAt)
        let vocabulary = vocabulary(for: note)
        speech.contextualVocabulary = vocabulary
        systemSpeech.contextualVocabulary = vocabulary
        clock?.cancel()
        clock = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.elapsed = Date().timeIntervalSince(startedAt) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        startRecognisers(for: note)
    }

    private func startRecognisers(for note: MeetingNote) {
        if let testFiles {
            speech.source = .file(testFiles.microphone)
            if let system = testFiles.system, !note.isInPerson {
                systemSpeech.source = .file(system)
                Task { await systemSpeech.start() }
            }
        } else {
            // On a call the mic must not hear the speakers, or "Them" turns up on both channels.
            speech.source = .microphone(echoCancelled: !note.isInPerson)
            if !note.isInPerson {
                systemSpeech.source = .systemAudio
                Task { await systemSpeech.start() }
            }
        }
        Task { await speech.start() }
    }

    func stop() {
        guard let id = activeID else { return }
        speech.stop()
        systemSpeech.stop()
        clock?.cancel()
        clock = nil
        for channel in AudioChannel.allCases { flushPending(channel, to: id) }
        liveText = [:]
        modify(id) { $0.endedAt = Date() }
        activeID = nil
        saveNow(id)
    }

    func toggleCapture(_ id: UUID) {
        activeID == id ? stop() : start(id)
    }

    /// Switch between a call (mic is you, system audio is them) and everyone in the room.
    /// Mid-capture this restarts the recognisers with the right sources.
    func setInPerson(_ inPerson: Bool, for id: UUID) {
        modify(id) { $0.isInPerson = inPerson }
        guard activeID == id, let note = note(id: id) else { return }
        speech.stop()
        systemSpeech.stop()
        for channel in AudioChannel.allCases { flushPending(channel, to: id) }
        liveText = [:]
        startRecognisers(for: note)
    }

    /// Keep the last stretch of what was said. Bound to ⌥⌘I so it works from inside the
    /// meeting app without switching windows.
    @discardableResult
    func markInsight(category: CaptureCategory = .insight) -> Bool {
        guard let id = activeID, let note = note(id: id) else { NSSound.beep(); return false }
        let now = max(latestTime, elapsed)
        var text = note.recentTranscript(before: now, window: Self.markWindow)
        for channel in AudioChannel.allCases {
            for extra in [pending[channel]?.text, liveText[channel]] {
                let t = (extra ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { text = (text + " " + t).trimmingCharacters(in: .whitespaces) }
            }
        }
        guard !text.isEmpty else { NSSound.beep(); return false }
        let recent = note.transcript.last { $0.end >= now - Self.markWindow }
        let capture = Capture(category: category, text: text, at: max(0, now - Self.markWindow / 2),
                              sentiment: detector.sentiment(of: text), source: .marked, isKept: true,
                              speaker: recent.map { note.speakerLabel(of: $0) })
        modify(id) { $0.captures.append(capture) }
        return true
    }

    func addCapture(to id: UUID, text: String, category: CaptureCategory) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let at = activeID == id ? elapsed : (note(id: id)?.transcript.last?.end ?? 0)
        let capture = Capture(category: category, text: trimmed, at: at, sentiment: detector.sentiment(of: trimmed),
                              source: .typed, isKept: true)
        modify(id) { $0.captures.append(capture) }
    }

    func keep(_ captureID: UUID, in id: UUID) {
        modify(id) { note in
            if let i = note.captures.firstIndex(where: { $0.id == captureID }) { note.captures[i].isKept = true }
        }
    }

    func keepAllSuggestions(in id: UUID) {
        modify(id) { note in
            for i in note.captures.indices { note.captures[i].isKept = true }
        }
    }

    func remove(_ captureID: UUID, from id: UUID) {
        modify(id) { $0.captures.removeAll { $0.id == captureID } }
    }

    func setCategory(_ category: CaptureCategory, for captureID: UUID, in id: UUID) {
        modify(id) { note in
            if let i = note.captures.firstIndex(where: { $0.id == captureID }) {
                note.captures[i].category = category
                note.captures[i].isKept = true
            }
        }
    }

    func setSentiment(_ sentiment: Sentiment, for captureID: UUID, in id: UUID) {
        modify(id) { note in
            if let i = note.captures.firstIndex(where: { $0.id == captureID }) { note.captures[i].sentiment = sentiment }
        }
    }

    // MARK: - Speakers

    func setSpeaker(_ label: String, for segmentID: UUID, in id: UUID) {
        modify(id) { $0.setSpeaker(label, for: segmentID) }
    }

    func relabelSpeaker(_ old: String, to new: String, in id: UUID) {
        modify(id) { $0.relabel(old, to: new) }
    }

    func confirmSpeaker(_ label: String, in id: UUID) {
        modify(id) { $0.confirmSpeaker(label) }
    }

    func draftWrapUp(_ id: UUID) {
        modify(id) { MeetingWrapUp.draft(&$0) }
    }

    // MARK: - Output

    func markdown(for id: UUID) -> String? {
        note(id: id).map { MeetingMarkdown.render($0) }
    }

    func markdownURL(for id: UUID) -> URL? {
        note(id: id).map { store.markdownURL(for: $0) }
    }

    func copyMarkdown(_ id: UUID) {
        guard let md = markdown(for: id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    func revealMarkdown(_ id: UUID) {
        saveNow(id)
        guard let url = markdownURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func exportMarkdown(_ id: UUID) {
        guard let note = note(id: id), let md = markdown(for: id) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = MeetingMarkdown.filename(for: note)
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? md.write(to: url, atomically: true, encoding: .utf8)
    }

    func setMarkdownDirectory(_ url: URL) {
        try? store.setMarkdownDirectory(url)
        Preferences.shared.meetingNotesDirectory = url.path
    }

    // MARK: - Status

    /// One line about the remote channel for the footer, or nil when it isn't in use.
    var systemAudioStatus: String? {
        guard let note = active, !note.isInPerson else { return nil }
        switch systemSpeech.state {
        case .listening:
            return systemSpeech.systemAudioPeak > 0.002 ? "System audio: hearing the call" : "System audio: quiet so far"
        case .preparing, .requestingPermission: return "System audio: starting…"
        case .downloadingModel: return "System audio: downloading model…"
        case .unavailable(let message): return "System audio: \(message)"
        case .denied: return "System audio: denied"
        case .idle: return nil
        }
    }

    /// True once system audio has been listening a while and nothing has been heard, which
    /// is what a refused "System Audio Recording" permission looks like.
    var systemAudioMayBeBlocked: Bool {
        guard let note = active, !note.isInPerson, systemSpeech.state == .listening else { return false }
        return elapsed > 20 && systemSpeech.systemAudioPeak <= 0.002
    }

    // MARK: - Transcript

    private func offset(for channel: AudioChannel) -> TimeInterval {
        let service = channel == .microphone ? speech : systemSpeech
        guard let startedAt, let audioStartedAt = service.audioStartedAt else { return 0 }
        return audioStartedAt.timeIntervalSince(startedAt)
    }

    private func handle(_ update: TranscriptUpdate, on channel: AudioChannel) {
        guard let id = activeID else { return }
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !update.isFinal {
            liveText[channel] = text
            return
        }
        liveText[channel] = nil
        guard !text.isEmpty, let note = note(id: id) else { return }
        let start = offset(for: channel) + update.start
        let end = offset(for: channel) + update.end
        latestTime = max(latestTime, end)

        var segment = TranscriptSegment(start: start, end: end, text: text, channel: channel)
        if let suggestion = labeler.suggest(for: segment, in: note) {
            segment.speaker = suggestion.speaker
            segment.speakerIsSuggested = true
        }
        let speaker = note.speakerLabel(of: segment)
        modify(id) { n in
            // Two channels settle independently; keep the transcript in time order.
            let i = n.transcript.lastIndex { $0.start <= segment.start }.map { $0 + 1 } ?? 0
            n.transcript.insert(segment, at: i)
        }

        // Sentences can straddle two settled results, so hold the tail until it ends.
        var buffer = pending[channel] ?? (text: "", start: start)
        buffer.text = buffer.text.isEmpty ? text : buffer.text + " " + text
        var sentences = InsightDetector.sentences(in: buffer.text)
        let last = sentences.last ?? ""
        let complete: Bool
        if let terminator = last.last, terminator == "." || terminator == "?" || terminator == "!" {
            complete = true
        } else {
            complete = false
            sentences.removeLast()
        }
        let span = max(1, end - buffer.start)
        for (i, sentence) in sentences.enumerated() {
            let at = buffer.start + span * Double(i) / Double(max(1, sentences.count))
            suggest(sentence, at: at, channel: channel, speaker: speaker, in: id)
        }
        pending[channel] = complete ? nil : (text: last, start: end)
    }

    private func flushPending(_ channel: AudioChannel, to id: UUID) {
        guard let buffer = pending[channel] else { return }
        pending[channel] = nil
        let tail = buffer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty, let note = note(id: id) else { return }
        let speaker = note.transcript.last { $0.channel == channel }.map { note.speakerLabel(of: $0) }
            ?? note.defaultSpeaker(for: channel)
        suggest(tail, at: buffer.start, channel: channel, speaker: speaker, in: id)
    }

    private func suggest(_ sentence: String, at: TimeInterval, channel: AudioChannel, speaker: String, in id: UUID) {
        guard let note = note(id: id),
              let detection = detector.detect(sentence, from: channel, inPerson: note.isInPerson),
              !note.captures.contains(where: { $0.text == detection.text }) else { return }
        let capture = Capture(category: detection.category, text: detection.text, at: at,
                              sentiment: detection.sentiment, source: .detected, isKept: false, speaker: speaker)
        modify(id) { $0.captures.append(capture) }
        if VoiceFollowController.logsTranscript {
            NSLog("[meeting] %@ %@ (%@) ← %@: %@", speaker, detection.category.rawValue, detection.sentiment.rawValue, detection.cue, detection.text)
        }
    }

    /// Bias recognition towards the script being pitched and the names in the room.
    private func vocabulary(for note: MeetingNote) -> [String] {
        var words: [String] = []
        if let scriptID = note.scriptID, let doc = library?.document(id: scriptID) {
            words += VoiceFollowController.vocabulary(of: PhraseParser().parse(doc.text))
        }
        words += note.attendeeNames.flatMap { $0.split(separator: " ").map(String.init) }.filter { $0.count >= 3 }
        return Array(words.prefix(300))
    }
}
