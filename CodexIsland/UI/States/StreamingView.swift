import SwiftUI

struct StreamingView: View {
    var animationName: PetAnimation = .talkWalk
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        HStack(spacing: 8) {
            if settings.isDesktopPetEnabled {
                Color.clear
                    .frame(width: 28, height: 28)
            } else {
                RoamingPetView(
                    animationName: animationName,
                    form: evolutionStore.currentForm,
                    level: evolutionStore.level,
                    feedTrigger: evolutionStore.feedTrigger
                )
            }

            TokenInfoRow(style: settings.capsuleStyle)
        }
        .padding(.horizontal, 10)
        .frame(
            width: settings.capsuleStyle.pillSize.width,
            height: settings.capsuleStyle.pillSize.height,
            alignment: .leading
        )
    }
}
