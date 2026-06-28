import SwiftUI

struct StreamingView: View {
    var animationName: PetAnimation = .talkWalk
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        ZStack(alignment: .leading) {
            RoamingPetView(
                animationName: animationName,
                stage: evolutionStore.stage,
                prestigeLevel: evolutionStore.prestigeLevel,
                capsuleStyle: settings.capsuleStyle,
                feedTrigger: evolutionStore.feedTrigger,
                evolutionTrigger: evolutionStore.evolutionTrigger
            )
            .zIndex(0)

            TokenInfoRow(style: settings.capsuleStyle)
                .padding(.horizontal, 12)
                .zIndex(1)
        }
        .frame(
            width: settings.capsuleStyle.pillSize.width,
            height: settings.capsuleStyle.pillSize.height
        )
    }
}
