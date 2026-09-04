import Foundation
import Observation
import PrompterCore

/// The script library as the UI sees it: an ordered list, a selection, and autosave.
@MainActor
@Observable
final class LibraryModel {
    private let store: ScriptLibrary
    private(set) var documents: [ScriptDocument] = []
    var selectedID: UUID?
    var searchText = "" {
        didSet { refresh() }
    }
    private var autosaveTask: Task<Void, Never>?

    init(store: ScriptLibrary) {
        self.store = store
        refresh()
    }

    var selected: ScriptDocument? {
        get { selectedID.flatMap { id in documents.first { $0.id == id } } }
    }

    func document(id: UUID) -> ScriptDocument? { store.script(id: id) }

    /// Favourites first, then most recently updated. Archived scripts stay out of the way.
    func refresh() {
        let all = store.search(searchText).filter { !$0.isArchived }
        documents = all.sorted {
            if $0.isFavourite != $1.isFavourite { return $0.isFavourite }
            return $0.updatedAt > $1.updatedAt
        }
    }

    func recentDocuments(limit: Int) -> [ScriptDocument] {
        store.all().filter { $0.lastPresentedAt != nil && !$0.isArchived }
            .sorted { ($0.lastPresentedAt ?? .distantPast) > ($1.lastPresentedAt ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    @discardableResult
    func createNew(title: String = "", text: String = "") -> ScriptDocument {
        let doc = (try? store.save(ScriptDocument(title: title.isEmpty ? "Untitled" : title, text: text))) ?? ScriptDocument(title: title, text: text)
        refresh()
        selectedID = doc.id
        return doc
    }

    func saveClipboardPrompt(title: String, text: String) -> ScriptDocument? {
        // Don't pile up duplicates when the same text is prompted repeatedly.
        if var existing = store.all().first(where: { $0.text == text }) {
            existing.lastPresentedAt = Date()
            let saved = try? store.save(existing)
            refresh()
            return saved
        }
        var doc = ScriptDocument(title: title, text: text)
        doc.lastPresentedAt = Date()
        let saved = try? store.save(doc)
        refresh()
        return saved
    }

    func update(_ document: ScriptDocument) {
        // Optimistic in-memory update so typing feels instant; disk write is debounced.
        if let i = documents.firstIndex(where: { $0.id == document.id }) {
            documents[i] = document
        }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            _ = try? self?.store.save(document)
            self?.refresh()
        }
    }

    func markPresented(_ id: UUID) {
        guard var doc = store.script(id: id) else { return }
        doc.lastPresentedAt = Date()
        _ = try? store.save(doc)
        refresh()
    }

    func toggleFavourite(_ id: UUID) {
        guard var doc = store.script(id: id) else { return }
        doc.isFavourite.toggle()
        _ = try? store.save(doc)
        refresh()
    }

    func duplicate(_ id: UUID) {
        guard let doc = store.script(id: id) else { return }
        let copy = ScriptDocument(title: doc.title + " copy", text: doc.text)
        _ = try? store.save(copy)
        refresh()
        selectedID = copy.id
    }

    func delete(_ id: UUID) {
        _ = try? store.delete(id: id)
        if selectedID == id { selectedID = nil }
        refresh()
    }
}
