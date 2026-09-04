import SwiftUI
import PrompterCore

/// Things the prompt's controls can ask the app to do.
struct PromptActions {
    var hide: () -> Void
    var endSession: () -> Void
    var openSettings: () -> Void
    var setStyle: (DeliveryStyle) -> Void
    var snapToCamera: () -> Void
}

/// The prompt itself: the current phrase sits at the top, nearest the camera, with the
/// Pace Dot beneath it and the next phrase quietly below. Controls only appear on hover.
struct PromptView: View {
    @Bindable var session: PromptSession
    var voice: VoiceFollowController
    var preferences: Preferences
    var actions: PromptActions

    @State private var hovering = false

    private var appearance: PromptAppearance { preferences.appearance }

    var body: some View {
        VStack(spacing: appearance.lineSpacing) {
            if appearance.showPrevious {
                phraseLine(session.previousPhrase, state: .spoken)
            }
            phraseLine(session.currentPhrase, state: .current)
            if session.mode == .coach {
                PaceDotView(session: session, tint: appearance.theme.foreground)
                    .padding(.horizontal, 12)
                    .opacity(session.isRunning ? 1 : 0.35)
            }
            phraseLine(session.nextPhrase, state: .upcoming)
        }
        .overlay(alignment: .topTrailing) { statusBadge.padding(.top, 7).padding(.trailing, 9) }
        .overlay(alignment: .bottom) {
            if hovering {
                controls
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PromptBackground(opacity: appearance.backgroundOpacity, theme: appearance.theme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.28), value: session.currentIndex)
        .animation(.easeInOut(duration: 0.2), value: session.isRunning)
        .animation(.easeOut(duration: 0.16), value: hovering)
    }

    // MARK: - Lines

    @ViewBuilder
    private func phraseLine(_ phrase: Phrase?, state: PhraseState) -> some View {
        Text(phrase?.text ?? " ")
            .font(font(for: state, emphasis: phrase?.emphasis ?? .normal))
            .foregroundStyle(appearance.theme.foreground)
            .opacity(state.opacity)
            .multilineTextAlignment(.center)
            .lineLimit(state == .current ? 3 : 2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
            .id("\(state)-\(phrase?.id ?? -1)")
            .transition(.opacity)
    }

    private func font(for state: PhraseState, emphasis: Emphasis) -> Font {
        let base = appearance.fontSize
        switch state {
        case .current:
            return .system(size: base, weight: emphasis == .strong ? .bold : .semibold, design: .default)
        case .spoken, .upcoming:
            return .system(size: base * 0.72, weight: .regular, design: .default)
        }
    }

    // MARK: - Status

    /// Only speaks up when something needs attention; a faint pulse when listening.
    @ViewBuilder
    private var statusBadge: some View {
        switch voice.speech.state {
        case .listening:
            ListeningPulse(tint: appearance.theme.foreground)
        case .preparing, .requestingPermission:
            statusLabel("Preparing…", symbol: "waveform")
        case .denied:
            statusLabel("Microphone access needed", symbol: "mic.slash")
        case .unavailable:
            statusLabel("Voice Follow unavailable", symbol: "mic.slash")
        case .idle:
            EmptyView()
        }
    }

    private func statusLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(appearance.theme.foreground.opacity(0.5))
            .labelStyle(.titleAndIcon)
    }

    // MARK: - Hover controls

    private var controls: some View {
        HStack(spacing: 2) {
            controlButton(session.isRunning ? "pause.fill" : "play.fill",
                          help: session.isRunning ? "Pause (Space)" : "Start (Space)") { session.toggleRunning() }
            controlButton("chevron.left", help: "Previous phrase (←)") { session.retreat() }
            controlButton("chevron.right", help: "Next phrase (→)") { session.advance() }
            divider
            Menu {
                ForEach(DeliveryStyle.allCases) { style in
                    Button {
                        actions.setStyle(style)
                    } label: {
                        if style == session.style { Label(style.displayName, systemImage: "checkmark") }
                        else { Text(style.displayName) }
                    }
                }
            } label: {
                Text(session.style.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Delivery style")
            divider
            controlButton("textformat.size.smaller", help: "Smaller text (−)") { preferences.adjustFontSize(by: -2) }
            controlButton("textformat.size.larger", help: "Larger text (+)") { preferences.adjustFontSize(by: 2) }
            controlButton("camera.viewfinder", help: "Snap under camera") { actions.snapToCamera() }
            divider
            controlButton("checkmark.circle", help: "End session & review (⌥⌘.)") { actions.endSession() }
            controlButton("gearshape", help: "Settings") { actions.openSettings() }
            controlButton("xmark", help: "Hide (Esc)") { actions.hide() }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .environment(\.colorScheme, appearance.theme == .dark ? .dark : .light)
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.15)).frame(width: 1, height: 14).padding(.horizontal, 4)
    }

    private func controlButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

enum PhraseState: Hashable {
    case spoken, current, upcoming

    var opacity: Double {
        switch self {
        case .spoken: 0.32
        case .current: 1.0
        case .upcoming: 0.55
        }
    }
}

enum PromptTheme: String, CaseIterable, Codable {
    case dark, light

    var foreground: Color {
        switch self {
        case .dark: .white
        case .light: .black
        }
    }
}

struct PromptAppearance: Equatable, Codable {
    var fontSize: CGFloat = 30
    var lineSpacing: CGFloat = 8
    var backgroundOpacity: Double = 0.78
    var theme: PromptTheme = .dark
    var showPrevious = false
}

/// A 5pt dot that breathes slowly: "I'm listening", without demanding attention.
private struct ListeningPulse: View {
    var tint: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(tint.opacity(on ? 0.55 : 0.2))
            .frame(width: 5, height: 5)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .accessibilityLabel("Listening")
    }
}

private struct PromptBackground: View {
    var opacity: Double
    var theme: PromptTheme
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill((theme == .dark ? Color.black : Color.white).opacity(opacity))
        }
    }
}
