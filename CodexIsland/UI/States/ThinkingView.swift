import SwiftUI

struct ThinkingView: View {
    var feedTrigger: UUID?

    @State private var dotCount = 1
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 8) {
            PixelPetView(
                animationName: .thinkSweat,
                size: 22,
                feedTrigger: feedTrigger
            )

            Divider()
                .frame(width: 1, height: 18)
                .overlay(Color.white.opacity(0.20))

            HStack(spacing: 5) {
                Text("Thinking")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .lineLimit(1)

                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(index < dotCount ? 0.90 : 0.30))
                            .frame(width: 4, height: 4)
                            .scaleEffect(index < dotCount ? 1.18 : 0.82)
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.76)
                                    .delay(Double(index) * 0.05),
                                value: dotCount
                            )
                    }
                }
                .frame(width: 18, height: 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            dotCount = dotCount % 3 + 1
        }
    }
}
