import SwiftUI

struct StreamingView: View {
    var animationName: PetAnimation = .talkWalk
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        HStack(spacing: 10) {
            RoamingPetView(
                animationName: animationName,
                stage: evolutionStore.stage,
                prestigeLevel: evolutionStore.prestigeLevel,
                feedTrigger: evolutionStore.feedTrigger,
                evolutionTrigger: evolutionStore.evolutionTrigger
            )

            TokenInfoRow(style: settings.capsuleStyle)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(
            width: settings.capsuleStyle.pillSize.width,
            height: settings.capsuleStyle.pillSize.height,
            alignment: .leading
        )
    }
}
