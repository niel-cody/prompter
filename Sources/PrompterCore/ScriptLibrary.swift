import Foundation

/// A saved script. The text is the user's; everything derived (phrases, timing) is rebuilt
/// on demand and never stored.
public struct ScriptDocument: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastPresentedAt: Date?
    public var isFavourite: Bool
    public var isArchived: Bool

    public init(id: UUID = UUID(), title: String, text: String, createdAt: Date = Date(), updatedAt: Date = Date(),
                lastPresentedAt: Date? = nil, isFavourite: Bool = false, isArchived: Bool = false) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastPresentedAt = lastPresentedAt
        self.isFavourite = isFavourite
        self.isArchived = isArchived
    }

    public var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    /// A title derived from the first line when the user hasn't given one.
    public static func inferredTitle(from text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let cleaned = firstLine.replacingOccurrences(of: #"^[#>\-\*\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Untitled" }
        return cleaned.count > 60 ? String(cleaned.prefix(59)).trimmingCharacters(in: .whitespaces) + "…" : cleaned
    }
}

/// Local, file-per-script storage in the user's Application Support folder. Plain JSON: easy
/// to back up, inspect, or sync later without a migration story.
public final class ScriptLibrary: @unchecked Sendable {
    public let directory: URL
    private let queue = DispatchQueue(label: "Prompter.ScriptLibrary")
    private var cache: [UUID: ScriptDocument] = [:]
    private var loaded = false

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Prompter/Scripts`
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Prompter/Scripts", isDirectory: true)
    }

    public func all() -> [ScriptDocument] {
        queue.sync {
            loadIfNeeded()
            return cache.values.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    public func script(id: UUID) -> ScriptDocument? {
        queue.sync { loadIfNeeded(); return cache[id] }
    }

    @discardableResult
    public func save(_ document: ScriptDocument) throws -> ScriptDocument {
        try queue.sync {
            loadIfNeeded()
            var doc = document
            doc.updatedAt = Date()
            let data = try JSONEncoder.library.encode(doc)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: doc.id), options: .atomic)
            cache[doc.id] = doc
            return doc
        }
    }

    public func delete(id: UUID) throws {
        try queue.sync {
            loadIfNeeded()
            cache.removeValue(forKey: id)
            let u = url(for: id)
            if FileManager.default.fileExists(atPath: u.path) {
                try FileManager.default.removeItem(at: u)
            }
        }
    }

    public func search(_ query: String) -> [ScriptDocument] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all() }
        return all().filter { $0.title.lowercased().contains(q) || $0.text.lowercased().contains(q) }
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file), let doc = try? JSONDecoder.library.decode(ScriptDocument.self, from: data) {
                cache[doc.id] = doc
            }
        }
    }
}

extension JSONEncoder {
    static let library: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let library: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
