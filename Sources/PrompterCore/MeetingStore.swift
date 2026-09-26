import Foundation

/// File-per-meeting storage. JSON is the source of truth (reliable to reload); every save
/// also rewrites the Markdown mirror, which is the copy meant to be read, grepped and fed
/// to other tools. Point `markdownDirectory` at an Obsidian vault and the notes just appear.
public final class MeetingStore: @unchecked Sendable {
    public let directory: URL
    public private(set) var markdownDirectory: URL
    private let queue = DispatchQueue(label: "Prompter.MeetingStore")
    private var cache: [UUID: MeetingNote] = [:]
    /// Markdown filename each note was last written under, so a retitle removes the old file.
    private var markdownNames: [UUID: String] = [:]
    private var loaded = false

    public init(directory: URL, markdownDirectory: URL? = nil) {
        self.directory = directory
        self.markdownDirectory = markdownDirectory ?? directory
    }

    /// `~/Library/Application Support/Prompter/Meetings`
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Prompter/Meetings", isDirectory: true)
    }

    public func all() -> [MeetingNote] {
        queue.sync {
            loadIfNeeded()
            return cache.values.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func note(id: UUID) -> MeetingNote? {
        queue.sync { loadIfNeeded(); return cache[id] }
    }

    @discardableResult
    public func save(_ note: MeetingNote) throws -> MeetingNote {
        try queue.sync {
            loadIfNeeded()
            var doc = note
            doc.updatedAt = Date()
            let data = try JSONEncoder.library.encode(doc)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: jsonURL(for: doc.id), options: .atomic)
            cache[doc.id] = doc
            try writeMarkdown(doc)
            return doc
        }
    }

    public func delete(id: UUID) throws {
        try queue.sync {
            loadIfNeeded()
            cache.removeValue(forKey: id)
            let u = jsonURL(for: id)
            if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
            if let name = markdownNames.removeValue(forKey: id) {
                let m = markdownDirectory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: m.path) { try? FileManager.default.removeItem(at: m) }
            }
        }
    }

    /// Change where Markdown goes and rewrite every note there.
    public func setMarkdownDirectory(_ url: URL) throws {
        try queue.sync {
            loadIfNeeded()
            markdownDirectory = url
            markdownNames.removeAll()
            for note in cache.values { try writeMarkdown(note) }
        }
    }

    /// Where the Markdown for a note lives (whether or not it's been written yet).
    public func markdownURL(for note: MeetingNote) -> URL {
        markdownDirectory.appendingPathComponent(MeetingMarkdown.filename(for: note))
    }

    public func search(_ query: String) -> [MeetingNote] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all() }
        return all().filter {
            $0.title.lowercased().contains(q)
                || $0.notes.lowercased().contains(q)
                || $0.captures.contains { c in c.text.lowercased().contains(q) }
                || $0.transcriptText.lowercased().contains(q)
        }
    }

    private func writeMarkdown(_ note: MeetingNote) throws {
        let name = MeetingMarkdown.filename(for: note)
        if let old = markdownNames[note.id], old != name {
            let stale = markdownDirectory.appendingPathComponent(old)
            if FileManager.default.fileExists(atPath: stale.path) { try? FileManager.default.removeItem(at: stale) }
        }
        try FileManager.default.createDirectory(at: markdownDirectory, withIntermediateDirectories: true)
        try MeetingMarkdown.render(note).write(to: markdownDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        markdownNames[note.id] = name
    }

    private func jsonURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let note = try? JSONDecoder.library.decode(MeetingNote.self, from: data) {
                cache[note.id] = note
                markdownNames[note.id] = MeetingMarkdown.filename(for: note)
            }
        }
    }
}
