import SwiftUI
import PrompterCore

/// A script in the sidebar: title, length, when it changed.
struct ScriptRow: View {
    let document: ScriptDocument

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.title).lineLimit(1)
                Text("\(document.wordCount) words · \(document.updatedAt, format: .relative(presentation: .named))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if document.isFavourite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// The script editor: a title, a place to write, and one button that matters.
struct ScriptEditorView: View {
    @State var document: ScriptDocument
    var library: LibraryModel
    var prompt: PromptController
    @FocusState private var textFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Title", text: $document.title)
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .semibold))
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 10)
            TextEditor(text: $document.text)
                .font(.system(size: 15))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 24)
                .focused($textFocused)
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: document) { _, doc in library.update(doc) }
        .onAppear { textFocused = true }
        .id(document.id)
        .toolbar {
            ToolbarItemGroup {
                Button { library.toggleFavourite(document.id) } label: {
                    Label("Favourite", systemImage: document.isFavourite ? "star.fill" : "star")
                }
                Button { prompt.present(document) } label: {
                    Label("Present", systemImage: "play.fill")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            let script = PhraseParser().parse(document.text)
            let seconds = prompt.session.style.profile.estimatedDuration(of: script)
            Text("\(script.wordCount) words")
            Text("about \(Self.duration(seconds)) at \(prompt.session.style.displayName)")
            Text("\(script.phrases.count) phrases")
            Spacer()
            Text("Autosaved")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }

    private static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s < 60 { return "\(s) s" }
        let m = s / 60, r = s % 60
        return r == 0 ? "\(m) min" : "\(m) min \(r) s"
    }
}
