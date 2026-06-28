import SwiftUI

@MainActor
final class NotchIslandContentModel: ObservableObject {
    @Published var isExpanded = false
}

struct NotchIslandView: View {
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject var model: NotchIslandContentModel
    let onRestingShapeChanged: (IslandShape) -> Void

    var body: some View {
        let containerShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            Group {
                if model.isExpanded {
                    ExpandedPanelView(feedTrigger: eventBus.petFeedTrigger)
                        .transition(.opacity)
                } else {
                    pillContent
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: model.isExpanded)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: eventBus.sessionState)
        }
        .background(containerShape.fill(Color.black))
        .clipShape(containerShape)
        .shadow(
            color: .black.opacity(model.isExpanded ? 0.35 : 0.0),
            radius: model.isExpanded ? 18 : 0
        )
        .contentShape(Rectangle())
        .onAppear {
            onRestingShapeChanged(shape(for: eventBus.sessionState))
        }
        .onChange(of: eventBus.sessionState) { state in
            onRestingShapeChanged(shape(for: state))
        }
    }

    private var compactContent: some View {
        IdleView(
            animationName: petAnimation,
            feedTrigger: eventBus.petFeedTrigger
        )
    }

    @ViewBuilder
    private var pillContent: some View {
        StreamingView(animationName: petAnimation)
    }

    private var petAnimation: PetAnimation {
        PetAnimation.from(state: eventBus.sessionState)
    }

    private var cornerRadius: CGFloat {
        model.isExpanded ? IslandShape.expandedCornerRadius : IslandShape.capsuleCornerRadius
    }

    private func shape(for state: CodexSessionState) -> IslandShape {
        .pill
    }
}
