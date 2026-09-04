import SwiftUI
import PrompterCore

/// The prompt itself: a short stack of phrases centred under the camera. Previous fades,
/// current is crisp, next is there but quiet. Nothing else competes for attention.
struct PromptView: View {
    @Bindable var session: PromptSession
    var appearance: PromptAppearance

    var body: some View {
        VStack(spacing: appearance.lineSpacing) {
            phraseLine(session.previousPhrase, state: .spoken)
            phraseLine(session.currentPhrase, state: .current)
            phraseLine(session.nextPhrase, state: .upcoming)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PromptBackground(opacity: appearance.backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.28), value: session.currentIndex)
    }

    @ViewBuilder
    private func phraseLine(_ phrase: Phrase?, state: PhraseState) -> some View {
        Text(phrase?.text ?? " ")
            .font(font(for: state, emphasis: phrase?.emphasis ?? .normal))
            .foregroundStyle(state.color(theme: appearance.theme))
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

    func color(theme: PromptTheme) -> Color {
        switch theme {
        case .dark: .white
        case .light: .black
        }
    }
}

enum PromptTheme: String, CaseIterable, Codable {
    case dark, light
}

struct PromptAppearance: Equatable, Codable {
    var fontSize: CGFloat = 30
    var lineSpacing: CGFloat = 10
    var backgroundOpacity: Double = 0.78
    var theme: PromptTheme = .dark
}

private struct PromptBackground: View {
    var opacity: Double
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(Color.black.opacity(opacity))
        }
    }
}
