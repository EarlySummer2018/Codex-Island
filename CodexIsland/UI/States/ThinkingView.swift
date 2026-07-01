import SwiftUI

struct ThinkingView: View {
    var feedTrigger: UUID?

    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        HStack(spacing: 8) {
            PixelPetView(
                animationName: PetAnimation.from(state: .thinking, level: evolutionStore.level),
                size: 22,
                form: evolutionStore.currentForm,
                level: evolutionStore.level,
                feedTrigger: feedTrigger
            )

            Divider()
                .frame(width: 1, height: 18)
                .overlay(Color.white.opacity(0.20))

            Text("Thinking")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
}
