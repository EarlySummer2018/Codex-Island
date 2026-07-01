import SwiftUI

struct IdleView: View {
    let animationName: PetAnimation
    var feedTrigger: UUID?

    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            PixelPetView(
                animationName: animationName,
                size: 24,
                form: evolutionStore.currentForm,
                level: evolutionStore.level,
                feedTrigger: feedTrigger
            )
            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }
}
