import SwiftUI

@MainActor
final class NotchIslandContentModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isExpandedContainer = false
}

struct NotchIslandView: View {
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject var model: NotchIslandContentModel
    let onRestingShapeChanged: (IslandShape) -> Void

    var body: some View {
        let containerShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack(alignment: .top) {
            Group {
                if model.isExpanded {
                    ExpandedPanelView()
                        .transition(.opacity)
                } else {
                    pillContent
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: model.isExpanded)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: model.isExpandedContainer)
            .animation(.spring(response: 0.30, dampingFraction: 0.82), value: eventBus.sessionState)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(containerShape.fill(Color.black))
        .clipShape(containerShape)
        .contentShape(Rectangle())
        .onAppear {
            onRestingShapeChanged(shape(for: eventBus.sessionState))
        }
        .onChange(of: eventBus.sessionState) { state in
            onRestingShapeChanged(shape(for: state))
        }
    }

    @ViewBuilder
    private var pillContent: some View {
        StreamingView(animationName: petAnimation)
    }

    private var petAnimation: PetAnimation {
        PetAnimation.from(state: eventBus.sessionState)
    }

    private var cornerRadius: CGFloat {
        model.isExpandedContainer ? IslandShape.expandedCornerRadius : IslandShape.capsuleCornerRadius
    }

    private func shape(for state: CodexSessionState) -> IslandShape {
        .pill
    }
}
