import AVFoundation
import AppKit
import SwiftUI
import PrompterCore

struct SettingsView: View {
    var prompt: PromptController
    var meetings: MeetingController
    var preferences: Preferences

    private enum Pane: String, CaseIterable, Identifiable {
        case general = "General", prompt = "Prompt", meetings = "Meetings", shortcuts = "Shortcuts", privacy = "Privacy"
        var id: String { rawValue }
    }

    @State private var pane: Pane = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 400)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Group {
                switch pane {
                case .general: GeneralSettings(prompt: prompt, preferences: preferences)
                case .prompt: PromptSettings(preferences: preferences)
                case .meetings: MeetingSettings(meetings: meetings, preferences: preferences)
                case .shortcuts: ShortcutsSettings()
                case .privacy: PrivacySettings()
                }
            }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettings: View {
    var prompt: PromptController
    var preferences: Preferences

    var body: some View {
        Form {
            Picker("Delivery", selection: Binding(get: { preferences.style }, set: { prompt.setStyle($0) })) {
                ForEach(DeliveryStyle.allCases) { Text($0.displayName).tag($0) }
            }
            Text(preferences.style.summary)
                .font(.callout).foregroundStyle(.secondary)

            Picker("Mode", selection: Binding(get: { preferences.mode }, set: { prompt.setMode($0) })) {
                ForEach(ReadingMode.allCases) { Text($0.displayName).tag($0) }
            }
            Text(modeSummary)
                .font(.callout).foregroundStyle(.secondary)

            Toggle("Voice Follow", isOn: Binding(get: { preferences.voiceFollowEnabled }, set: { prompt.setVoiceFollow($0) }))
                .disabled(preferences.mode != .coach)
            Text("Listens while you present and keeps your place. Audio is processed on this Mac and never stored.")
                .font(.callout).foregroundStyle(.secondary)

            if preferences.mode == .classic {
                Slider(value: Binding(get: { preferences.classicScrollSpeed }, set: { preferences.classicScrollSpeed = $0 }),
                       in: 0.5...2.0, step: 0.05) { Text("Scroll speed") }
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }

    private var modeSummary: String {
        switch preferences.mode {
        case .coach: "Phrase by phrase, following your voice, with the Pace Dot."
        case .classic: "The whole script scrolls past a reading line at a steady rate."
        case .manual: "Phrase by phrase; you advance with the arrow keys."
        }
    }
}

private struct PromptSettings: View {
    var preferences: Preferences

    var body: some View {
        Form {
            Slider(value: Binding(get: { Double(preferences.appearance.fontSize) }, set: { preferences.appearance.fontSize = CGFloat($0) }),
                   in: 18...56, step: 1) { Text("Text size") }
            Slider(value: Binding(get: { preferences.appearance.backgroundOpacity }, set: { preferences.appearance.backgroundOpacity = $0 }),
                   in: 0.2...1.0) { Text("Background") }
            Picker("Appearance", selection: Binding(get: { preferences.appearance.theme }, set: { preferences.appearance.theme = $0 })) {
                Text("Dark").tag(PromptTheme.dark)
                Text("Light").tag(PromptTheme.light)
            }
            .pickerStyle(.segmented)
            Toggle("Show the previous phrase", isOn: Binding(get: { preferences.appearance.showPrevious }, set: { preferences.appearance.showPrevious = $0 }))
            Text("Keeping only the current and next phrase on screen keeps your eyes closest to the camera.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }
}

private struct MeetingSettings: View {
    var meetings: MeetingController
    var preferences: Preferences

    var body: some View {
        Form {
            Section {
                LabeledContent("Markdown notes") {
                    Text(meetings.markdownDirectory.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Button("Choose Folder…") { chooseFolder() }
                    Button("Use Default") {
                        preferences.meetingNotesDirectory = nil
                        meetings.setMarkdownDirectory(MeetingStore.defaultDirectory())
                        preferences.meetingNotesDirectory = nil
                    }
                    .disabled(preferences.meetingNotesDirectory == nil)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(meetings.markdownDirectory) }
                }
                Text("Every meeting is saved as JSON in Application Support and mirrored as a Markdown file with front matter here. Point this at an Obsidian vault or a notes folder and the files just appear.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Text("Nothing joins your calls. Prompter listens through the microphone with the same on-device recogniser as Voice Follow. To capture the other side of a video call, use speakers or a mic that hears them; audio is never written to disk.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Meeting notes will be written here as Markdown."
        panel.directoryURL = meetings.markdownDirectory
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        meetings.setMarkdownDirectory(url)
    }
}

private struct ShortcutsSettings: View {
    private let rows: [(String, String)] = [
        ("Prompt Clipboard", "⌥⌘V"),
        ("Show / Hide Prompt", "⌥⌘P"),
        ("Start / Pause", "⌥⌘↩"),
        ("Previous / Next phrase", "⌥⌘← / ⌥⌘→"),
        ("Previous / Next paragraph", "⌥⌘↑ / ⌥⌘↓"),
        ("Smaller / Larger text", "⌥⌘− / ⌥⌘="),
        ("End session & review", "⌥⌘."),
        ("Mark insight (meeting capture)", "⌥⌘I"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(rows, id: \.0) { row in
                    LabeledContent(row.0) {
                        Text(row.1).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("These work while Zoom, Teams, Chrome or Keynote has focus. After clicking the prompt, Space and the arrow keys work on their own.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }
}

private struct PrivacySettings: View {
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    var preferences = Preferences.shared

    var body: some View {
        Form {
            Section {
                Text("Your words stay on your Mac.")
                    .font(.headline)
                Text("Scripts and meeting notes are stored in Application Support as plain files. Speech recognition runs on this Mac using Apple's on-device models. Microphone and system audio are streamed to the recogniser and never written to disk. There is no account, no sync and no telemetry.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for updates automatically", isOn: Binding(get: { preferences.checkForUpdatesAutomatically },
                                                                       set: { preferences.checkForUpdatesAutomatically = $0 }))
                Text("Once a day Prompter asks GitHub for the latest release and offers to install it with one click. Nothing about you or your scripts is sent.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Microphone") {
                    Text(micLabel).foregroundStyle(.secondary)
                }
                if micStatus == .denied || micStatus == .restricted {
                    Button("Open Privacy Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                LabeledContent("System audio") {
                    Text("Asked when you first start a call in Meetings").foregroundStyle(.secondary)
                }
                Button("System Audio Recording Settings…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("Meetings hears the other side of a call from what your Mac is playing. macOS calls this System Audio Recording; nothing is installed and nothing is recorded.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private var micLabel: String {
        switch micStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Asked when you first start Voice Follow"
        @unknown default: "Unknown"
        }
    }
}
