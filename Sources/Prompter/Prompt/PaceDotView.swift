import SwiftUI
import PrompterCore

/// The conductor. A small dot travels beneath the current phrase at the ideal pace, rests
/// at the end for the suggested pause, then waits quietly. It never moves the text.
struct PaceDotView: View {
    var session: PromptSession
    var tint: Color

    private let dotSize: CGFloat = 7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !session.isRunning)) { context in
            let phase = currentPhase(at: context.date)
            GeometryReader { geo in
                let width = geo.size.width
                let x = xPosition(for: phase, width: width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.12))
                        .frame(height: 1.5)
                    dot(for: phase)
                        .offset(x: x - dotSize / 2)
                }
                .frame(width: width, height: geo.size.height, alignment: .leading)
            }
            .frame(height: dotSize + 4)
        }
        .accessibilityHidden(true)
    }

    private func currentPhase(at date: Date) -> PacePhase {
        guard let timing = session.currentTiming else { return .speaking(progress: 0) }
        return PaceConductor.phase(elapsed: session.phraseElapsed(at: date), timing: timing)
    }

    private func xPosition(for phase: PacePhase, width: CGFloat) -> CGFloat {
        switch phase {
        case .speaking(let p): return CGFloat(easeInOutSine(p)) * width
        case .pausing, .waiting: return width
        }
    }

    @ViewBuilder
    private func dot(for phase: PacePhase) -> some View {
        switch phase {
        case .speaking:
            Circle()
                .fill(tint)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: tint.opacity(0.6), radius: 4)
        case .pausing(let p):
            // Breathe out during the suggested pause: the ring opens as the pause fills.
            Circle()
                .strokeBorder(tint.opacity(0.9), lineWidth: 1.5)
                .frame(width: dotSize + CGFloat(p) * 6, height: dotSize + CGFloat(p) * 6)
                .opacity(1 - p * 0.5)
        case .waiting:
            Circle()
                .strokeBorder(tint.opacity(0.35), lineWidth: 1.5)
                .frame(width: dotSize + 6, height: dotSize + 6)
        }
    }

    /// A soft start and finish reads as "conducting" rather than "scrolling".
    private func easeInOutSine(_ t: Double) -> Double {
        -(cos(.pi * min(max(t, 0), 1)) - 1) / 2
    }
}
