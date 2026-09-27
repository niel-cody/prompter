import Foundation
import Observation
import PrompterCore

/// What the one window shows: the scripts you speak from and the meetings you capture,
/// with a single selection across both. Menu-bar actions and the window both go through
/// here so there is exactly one idea of "what's open".
@MainActor
@Observable
final class Workspace {
    enum Selection: Hashable {
        case script(UUID)
        case meeting(UUID)
    }

    enum Area {
        case scripts, meetings
    }

    let library: LibraryModel
    let meetings: MeetingController
    let prompt: PromptController

    init(library: LibraryModel, meetings: MeetingController, prompt: PromptController) {
        self.library = library
        self.meetings = meetings
        self.prompt = prompt
    }

    /// One search over scripts, notes and transcripts.
    var searchText = "" {
        didSet {
            library.searchText = searchText
            meetings.searchText = searchText
        }
    }

    /// Exactly one of the two models has a selection; the other is cleared.
    var selection: Selection? {
        get {
            if let id = library.selectedID { return .script(id) }
            if let id = meetings.selectedID { return .meeting(id) }
            return nil
        }
        set {
            switch newValue {
            case .script(let id):
                meetings.selectedID = nil
                library.selectedID = id
            case .meeting(let id):
                library.selectedID = nil
                meetings.selectedID = id
            case nil:
                library.selectedID = nil
                meetings.selectedID = nil
            }
        }
    }

    var selectedScript: ScriptDocument? {
        guard case .script(let id) = selection else { return nil }
        return library.documents.first { $0.id == id }
    }

    var selectedMeeting: MeetingNote? {
        guard case .meeting(let id) = selection else { return nil }
        return meetings.notes.first { $0.id == id }
    }

    @discardableResult
    func newScript(title: String = "", text: String = "") -> ScriptDocument {
        meetings.selectedID = nil
        return library.createNew(title: title, text: text)
    }

    @discardableResult
    func newMeeting(_ template: MeetingTemplate) -> MeetingNote {
        library.selectedID = nil
        return meetings.create(template: template)
    }

    /// Bring an area forward without losing a selection already in it.
    func focus(_ area: Area) {
        switch area {
        case .scripts:
            if case .script = selection { return }
            selection = library.documents.first.map { .script($0.id) }
        case .meetings:
            if case .meeting = selection { return }
            selection = meetings.notes.first.map { .meeting($0.id) }
        }
    }

    func duplicateScript(_ id: UUID) {
        meetings.selectedID = nil
        library.duplicate(id)
    }
}
