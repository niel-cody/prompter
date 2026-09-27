import SwiftUI
import PrompterCore

/// The one window. A sidebar with two sections, Scripts and Meetings, one New button and
/// one search; the detail is whichever you picked. Nothing else to find.
struct MainView: View {
    @Bindable var workspace: Workspace

    private var library: LibraryModel { workspace.library }
    private var meetings: MeetingController { workspace.meetings }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
                .toolbar {
                    ToolbarItem {
                        NewMenu(workspace: workspace)
                    }
                }
        } detail: {
            detail
        }
        .frame(minWidth: 880, minHeight: 520)
    }

    private var sidebar: some View {
        List(selection: $workspace.selection) {
            Section("Scripts") {
                if library.documents.isEmpty {
                    Text(workspace.searchText.isEmpty ? "Nothing to speak from yet" : "No matching scripts")
                        .foregroundStyle(.tertiary)
                }
                ForEach(library.documents) { doc in
                    ScriptRow(document: doc)
                        .tag(Workspace.Selection.script(doc.id))
                        .contextMenu {
                            Button(doc.isFavourite ? "Remove from Favourites" : "Add to Favourites") { library.toggleFavourite(doc.id) }
                            Button("Duplicate") { workspace.duplicateScript(doc.id) }
                            Divider()
                            Button("Delete", role: .destructive) { library.delete(doc.id) }
                        }
                }
            }
            Section("Meetings") {
                if meetings.notes.isEmpty {
                    Text(workspace.searchText.isEmpty ? "Nothing captured yet" : "No matching meetings")
                        .foregroundStyle(.tertiary)
                }
                ForEach(meetings.notes) { note in
                    MeetingRow(note: note, isActive: meetings.activeID == note.id)
                        .tag(Workspace.Selection.meeting(note.id))
                        .contextMenu {
                            Button("Reveal Markdown in Finder") { meetings.revealMarkdown(note.id) }
                            Divider()
                            Button("Delete", role: .destructive) { meetings.delete(note.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $workspace.searchText, placement: .sidebar, prompt: "Search")
    }

    @ViewBuilder private var detail: some View {
        if let doc = workspace.selectedScript {
            ScriptEditorView(document: doc, library: library, prompt: workspace.prompt)
        } else if let note = workspace.selectedMeeting {
            MeetingDetailView(note: note, meetings: meetings)
        } else {
            ContentUnavailableView {
                Label("Prompter", systemImage: "text.alignleft")
            } description: {
                Text("Write a script to speak from, or start meeting notes to capture what the room says back.\nCopy any text and press ⌥⌘V to prompt it straight away.")
            } actions: {
                Button("New Script") { workspace.newScript() }
                NewMeetingMenu(meetings: meetings, prominent: true) { workspace.newMeeting($0) }
            }
        }
    }
}

/// One "+" for everything you can make.
private struct NewMenu: View {
    var workspace: Workspace

    var body: some View {
        Menu {
            Button {
                workspace.newScript()
            } label: {
                Label("New Script", systemImage: "text.alignleft")
            }
            .keyboardShortcut("n")
            Section("New Meeting") {
                ForEach(MeetingTemplate.builtIn) { template in
                    Button {
                        workspace.newMeeting(template)
                    } label: {
                        Text(template.name)
                        Text(template.summary)
                    }
                }
            }
        } label: {
            Label("New", systemImage: "plus")
        }
        .help("New script, or meeting notes from a template")
    }
}
