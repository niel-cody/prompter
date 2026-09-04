import SwiftUI

/// One card, three sentences, one button. Value inside a minute.
struct OnboardingView: View {
    var onTrySample: () -> Void
    var onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Prompter")
                    .font(.system(size: 24, weight: .semibold))
                Text("A teleprompter that follows you, so you can look at the camera and just talk.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                step("rectangle.topthird.inset.filled", "The prompt sits right under your camera",
                     "Only the current phrase and the next one are shown, so your eyes stay on the lens.")
                step("waveform", "It listens and keeps your place",
                     "Pause, ad-lib, skip a line: the prompt waits or catches up. Your voice never leaves this Mac.")
                step("circle.fill", "A small dot keeps your pace",
                     "Stay level with it and you'll sound composed. It never drags the text along.")
            }
            HStack {
                Button("Not now", action: onSkip)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Try the sample", action: onTrySample)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
