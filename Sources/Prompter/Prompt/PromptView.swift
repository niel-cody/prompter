import SwiftUI
import PrompterCore

/// The prompt itself: the current phrase sits at the top, nearest the camera, with the
/// Pace Dot beneath it and the next phrase quietly below. Nothing else competes.
struct PromptView: View {
    @Bindable var session: PromptSession
    var appearance: PromptAppearance

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
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PromptBackground(opacity: appearance.backgroundOpacity, theme: appearance.theme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.28), value: session.currentIndex)
        .animation(.easeInOut(duration: 0.2), value: session.isRunning)
    }

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
