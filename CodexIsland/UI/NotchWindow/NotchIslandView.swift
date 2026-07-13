import SwiftUI

@MainActor
final class NotchIslandContentModel: ObservableObject {
    @Published var isExpanded = false
    @Published var isExpandedContainer = false
    @Published var expandedMode: NotchIslandExpandedMode = .dashboard
}

enum NotchIslandExpandedMode {
    case dashboard
    case settings
}

struct NotchIslandView: View {
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared
    @ObservedObject var model: NotchIslandContentModel

    var body: some View {
        let containerShape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack(alignment: .top) {
            Group {
                if model.isExpanded {
                    expandedContent
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
        .overlay(
            containerShape.stroke(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.20, blue: 0.56).opacity(model.isExpandedContainer ? 0.55 : 0.0),
                        Color(red: 0.52, green: 0.25, blue: 0.95).opacity(model.isExpandedContainer ? 0.34 : 0.0),
                        Color.white.opacity(model.isExpandedContainer ? 0.08 : 0.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: model.isExpandedContainer ? 1 : 0
            )
        )
        .clipShape(containerShape)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var pillContent: some View {
        StreamingView(animationName: petAnimation)
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch model.expandedMode {
        case .dashboard:
            ExpandedPanelView {
                model.expandedMode = .settings
            }
        case .settings:
            SettingsPanelView {
                model.expandedMode = .dashboard
            }
        }
    }

    private var petAnimation: PetAnimation {
        PetAnimation.from(
            state: eventBus.sessionState,
            activityKind: eventBus.activityKind,
            level: evolutionStore.level
        )
    }

    private var cornerRadius: CGFloat {
        model.isExpandedContainer ? IslandShape.expandedCornerRadius : IslandShape.capsuleCornerRadius
    }
}
