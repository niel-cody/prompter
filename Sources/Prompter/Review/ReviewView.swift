import SwiftUI
import PrompterCore

/// The post-session coaching card. A score, a headline, a few plain sentences. It coaches;
/// it doesn't audit.
struct ReviewView: View {
    let review: DeliveryReview
    let title: String
    var onPresentAgain: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Delivery")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer()
                if review.hasEnoughData {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(review.score, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("/ 10")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 18)

            Text(review.headline)
                .font(.system(size: 17, weight: .semibold))
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(review.notes.enumerated()), id: \.offset) { _, note in
                    Text(note)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if review.hasEnoughData {
                Divider().padding(.vertical, 18)
                HStack(spacing: 24) {
                    stat("Pace", value: review.averageWordsPerMinute.map { "\(Int($0.rounded())) wpm" } ?? "–")
                    stat("Pauses", value: review.pausesSuggested > 0 ? "\(review.pausesTaken) of \(review.pausesSuggested)" : "–")
                    stat("Covered", value: "\(Int((review.completion * 100).rounded()))%")
                    stat("Time", value: Self.duration(review.activeDuration))
                }
                .padding(.bottom, 22)
            } else {
                Spacer().frame(height: 22)
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("Present Again", action: onPresentAgain)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .padding(.top, 8)
        .frame(width: 440)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }
}
