import SwiftUI

struct RoamingPetView: View {
    let animationName: PetAnimation
    let stage: PetEvolutionStage
    let prestigeLevel: Int
    var capsuleStyle: CapsuleDisplayStyle = .large
    var feedTrigger: UUID?
    var evolutionTrigger: UUID?

    @State private var anchorIndex = 0
    @State private var movementTimer: Timer?

    var body: some View {
        PixelPetView(
            animationName: animationName,
            size: 22,
            stage: stage,
            prestigeLevel: prestigeLevel,
            feedTrigger: feedTrigger,
            evolutionTrigger: evolutionTrigger
        )
        .scaleEffect(x: isMovingLeft ? -1 : 1, y: 1)
        .position(x: currentAnchorX, y: 17)
        .animation(.easeInOut(duration: travelDuration), value: anchorIndex)
        .onAppear {
            startMovement()
        }
        .onDisappear {
            movementTimer?.invalidate()
            movementTimer = nil
        }
        .onChange(of: capsuleStyle) { _ in
            anchorIndex = min(anchorIndex, anchors.count - 1)
            startMovement()
        }
        .allowsHitTesting(false)
    }

    private var anchors: [CGFloat] {
        switch capsuleStyle {
        case .large:
            return [25, 113, 229, 317, 415]
        case .small:
            return [25, 235]
        }
    }

    private var travelDuration: Double {
        stage.rank >= PetEvolutionStage.glider.rank ? 0.85 : 1.15
    }

    private var dwellDuration: Double {
        stage.rank >= PetEvolutionStage.glider.rank ? 2.4 : 3.2
    }

    private var currentAnchorX: CGFloat {
        anchors[min(anchorIndex, anchors.count - 1)]
    }

    private var isMovingLeft: Bool {
        anchorIndex == anchors.indices.last
    }

    private func startMovement() {
        movementTimer?.invalidate()
        anchorIndex = min(anchorIndex, anchors.count - 1)

        let timer = Timer(timeInterval: dwellDuration, repeats: true) { _ in
            anchorIndex = (anchorIndex + 1) % anchors.count
        }

        movementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
