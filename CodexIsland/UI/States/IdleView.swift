import SwiftUI

struct IdleView: View {
    let animationName: PetAnimation
    var feedTrigger: UUID?

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            PixelPetView(
                animationName: animationName,
                size: 24,
                feedTrigger: feedTrigger
            )
            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }
}
