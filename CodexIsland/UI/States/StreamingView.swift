import SwiftUI

struct StreamingView: View {
    var animationName: PetAnimation = .talkWalk
    @ObservedObject private var settings = AppSettingsStore.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        let pillSize = settings.capsuleStyle.pillSize(desktopPetEnabled: settings.isDesktopPetEnabled)

        HStack(spacing: 8) {
            if !settings.isDesktopPetEnabled {
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
            width: pillSize.width,
            height: pillSize.height,
            alignment: .leading
        )
    }
}
