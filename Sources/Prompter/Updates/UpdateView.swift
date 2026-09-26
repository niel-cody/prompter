import AppKit
import SwiftUI
import PrompterCore

/// The one window for updates: checking, what's new, the steps of the install as they
/// happen, and what to do if it fails. Written for someone who has never unzipped anything:
/// one button, plain words, and it says what it is doing.
struct UpdateView: View {
    let checker: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            content
            buttons
        }
        .padding(22)
        .frame(width: 470)
    }

    private var release: ReleaseInfo? { checker.available }
    private var localBuild: String {
        (Bundle.main.object(forInfoDictionaryKey: "PrompterBuildCommit") as? String).map { " (local build \($0))" } ?? ""
    }
    private var version: String { release?.version ?? "" }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: String {
        switch checker.phase {
        case .idle, .checking: "Checking for updates…"
        case .upToDate: "You're up to date"
        case .available: "Prompter \(version) is ready"
        case .downloading, .verifying, .installing: "Updating to Prompter \(version)…"
        case .restarting: "Reopening Prompter…"
        case .failed: "Couldn't update"
        }
    }

    private var subtitle: String {
        switch checker.phase {
        case .idle, .checking: "Asking GitHub for the latest release. This takes a second."
        case .upToDate: "Prompter \(checker.currentVersion)\(localBuild) is the latest version."
        case .available: "You have \(checker.currentVersion). One click brings you up to date."
        case .downloading, .verifying, .installing:
            "Prompter keeps working until the last step. Your scripts, notes and settings stay exactly as they are."
        case .restarting: "Prompter will close and reopen by itself in a moment."
        case .failed: "You're still on Prompter \(checker.currentVersion), unchanged."
        }
    }

    // MARK: - Body

    @ViewBuilder private var content: some View {
        switch checker.phase {
        case .idle, .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for a newer version…").foregroundStyle(.secondary)
            }
        case .upToDate:
            EmptyView()
        case .available:
            notes
        case .downloading, .verifying, .installing, .restarting:
            steps
        case .failed(let message):
            Text(message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's new").font(.headline)
            ScrollView {
                Text(notesText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 60, maxHeight: 220)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            Text(footnote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesText: String {
        let text = release?.notes ?? ""
        return text.isEmpty ? "Fixes and improvements." : text
    }

    private var footnote: String {
        let size = release?.downloadSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let download = size.map { "a \($0) download" } ?? "a small download"
        return "Update Now is \(download). Prompter swaps in the new version and reopens itself. Nothing to unzip or drag."
    }

    // MARK: - Steps

    private enum Step: Int, CaseIterable {
        case download, verify, install, reopen
    }

    private var currentStep: Step {
        switch checker.phase {
        case .downloading: .download
        case .verifying: .verify
        case .installing: .install
        case .restarting: .reopen
        default: .download
        }
    }

    private func label(_ step: Step) -> String {
        switch step {
        case .download: "Download Prompter \(version)"
        case .verify: "Check it's genuinely Prompter"
        case .install: "Put the new version in place"
        case .reopen: "Reopen Prompter"
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Step.allCases, id: \.rawValue) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    icon(for: step).frame(width: 18)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(label(step))
                            .foregroundStyle(step.rawValue > currentStep.rawValue ? .secondary : .primary)
                        if step == .download, case .downloading(let received, let total) = checker.phase {
                            ProgressView(value: total.map { Double(received) / Double(max($0, 1)) })
                                .progressViewStyle(.linear)
                            Text(progressText(received: received, total: total))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func icon(for step: Step) -> some View {
        if step.rawValue < currentStep.rawValue {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if step == currentStep {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "circle").foregroundStyle(.quaternary)
        }
    }

    private func progressText(received: Int64, total: Int64?) -> String {
        let done = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        if let total, total > 0 {
            return "\(done) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
        }
        return "\(done) so far"
    }

    // MARK: - Buttons

    @ViewBuilder private var buttons: some View {
        HStack {
            switch checker.phase {
            case .idle, .checking:
                Spacer()
                Button("Cancel") { checker.dismiss() }.keyboardShortcut(.cancelAction)
            case .upToDate:
                Spacer()
                Button("OK") { checker.dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            case .available:
                Button("Skip This Version") { checker.skipThisVersion() }
                Spacer()
                Button("Later") { checker.later() }.keyboardShortcut(.cancelAction)
                Button("Update Now") { checker.install() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            case .downloading, .verifying:
                Spacer()
                Button("Cancel") { checker.cancelInstall() }.keyboardShortcut(.cancelAction)
            case .installing, .restarting:
                Spacer()
                Button("Cancel") {}.disabled(true)
            case .failed:
                Button("Open Download Page") { checker.openDownloadPage() }
                Spacer()
                Button("Not Now") { checker.dismiss() }.keyboardShortcut(.cancelAction)
                Button("Try Again") { checker.retry() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
