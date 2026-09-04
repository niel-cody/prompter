import SwiftUI
import PrompterCore

/// Classic mode: the whole script scrolls past a reading line at a steady rate. For people
/// who want a conventional teleprompter, or when Voice Follow isn't an option.
struct ClassicPromptView: View {
    @Bindable var session: PromptSession
    var preferences: Preferences

    @State private var startedAt: Date?
    @State private var banked: CGFloat = 0

    private var appearance: PromptAppearance { preferences.appearance }
    private var font: Font { .system(size: appearance.fontSize, weight: .medium) }

    /// Points per second, from the style's speaking rate: one line of text (~9 words at this
    /// width) should pass the reading line in the time it takes to say it.
    private var pointsPerSecond: CGFloat {
        let wordsPerSecond = session.style.profile.wordsPerMinute / 60
        let lineHeight = appearance.fontSize * 1.35
        let wordsPerLine = 9.0
        return CGFloat(wordsPerSecond / wordsPerLine) * lineHeight * CGFloat(preferences.classicScrollSpeed)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !session.isRunning)) { context in
                let offset = currentOffset(at: context.date)
                ZStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: appearance.fontSize * 0.6) {
                        ForEach(Array(session.script.sections.enumerated()), id: \.offset) { _, section in
                            Text(session.script.phrases[section.phraseRange].map(\.text).joined(separator: " "))
                                .font(font)
                                .foregroundStyle(appearance.theme.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, geo.size.height * 0.4)
                    .offset(y: -offset)

                    // Reading line, a third of the way down: eyes stay high, near the camera.
                    Rectangle()
                        .fill(appearance.theme.foreground.opacity(0.18))
                        .frame(height: 1)
                        .offset(y: geo.size.height * 0.4 + appearance.fontSize * 1.2)
                }
                .clipped()
            }
        }
        .onChange(of: session.isRunning) { _, running in
            if running { startedAt = Date() } else { banked = currentOffset(at: Date()); startedAt = nil }
        }
        .onChange(of: session.currentIndex) { _, index in
            // Manual jumps (or Restart) reposition the scroll.
            if index == 0 { banked = 0; startedAt = session.isRunning ? Date() : nil }
        }
    }

    private func currentOffset(at date: Date) -> CGFloat {
        guard let startedAt else { return banked }
        return banked + CGFloat(date.timeIntervalSince(startedAt)) * pointsPerSecond
    }
}
