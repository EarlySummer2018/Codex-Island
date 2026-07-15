import SwiftUI

struct DesktopPetView: View {
    @ObservedObject var controller: DesktopPetController
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var body: some View {
        VStack(spacing: 2) {
            PixelLevelBadgeView(
                level: evolutionStore.level,
                levelUpTrigger: evolutionStore.levelUpTrigger
            )
            .zIndex(1)

            PixelPetView(
                animationName: controller.animationName,
                size: controller.petSize * controller.userScale,
                form: evolutionStore.currentForm,
                level: evolutionStore.level,
                feedTrigger: evolutionStore.feedTrigger,
                isFacingLeft: controller.isFacingLeft
            )
            .scaleEffect(scale)
            .offset(y: petYOffset)
        }
        .offset(y: contentYOffset)
        .scaleEffect(controller.presentationScale)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: controller.phase)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: controller.action)
        .animation(.easeInOut(duration: 0.85), value: controller.presentationScale)
        .frame(width: controller.windowSize.width, height: controller.windowSize.height)
        .contentShape(Rectangle())
        .accessibilityLabel("Codex desktop pet")
    }

    private var scale: CGFloat {
        switch controller.action {
        case .hopping, .dodging:
            return 1.10
        case .dragging:
            return 1.12
        case .landing:
            return 0.96
        case .returning:
            return 0.94
        case .lookingAround:
            return 1.04
        case .idle, .strolling, .pausing:
            return 1.0
        }
    }

    private var contentYOffset: CGFloat {
        switch controller.action {
        case .dragging:
            return -8
        case .hopping, .dodging:
            return -4
        case .landing:
            return 4
        case .returning:
            return -2
        case .idle, .strolling, .pausing, .lookingAround:
            return 0
        }
    }

    private var petYOffset: CGFloat {
        switch controller.action {
        case .landing:
            return 4
        case .dragging:
            return -4
        case .hopping, .dodging:
            return -2
        case .idle, .strolling, .pausing, .lookingAround, .returning:
            return 0
        }
    }

}
