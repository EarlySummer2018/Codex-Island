import SwiftUI

struct RoamingPetView: View {
    let animationName: PetAnimation
    let form: PetForm
    let level: Int
    var feedTrigger: UUID?

    var body: some View {
        PixelPetView(
            animationName: animationName,
            size: 22,
            form: form,
            level: level,
            feedTrigger: feedTrigger
        )
        .frame(width: 28, height: 28)
        .allowsHitTesting(false)
    }
}
