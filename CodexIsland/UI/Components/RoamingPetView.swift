import SwiftUI

struct RoamingPetView: View {
    let animationName: PetAnimation
    let stage: PetEvolutionStage
    let prestigeLevel: Int
    var feedTrigger: UUID?
    var evolutionTrigger: UUID?

    var body: some View {
        PixelPetView(
            animationName: animationName,
            size: 22,
            stage: stage,
            prestigeLevel: prestigeLevel,
            feedTrigger: feedTrigger,
            evolutionTrigger: evolutionTrigger
        )
        .frame(width: 28, height: 28)
        .allowsHitTesting(false)
    }
}
