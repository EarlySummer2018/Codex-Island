import SwiftUI

struct AwaitingView: View {
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared

    var feedTrigger: UUID?

    var body: some View {
        HStack(spacing: 8) {
            PixelPetView(
                animationName: PetAnimation.from(state: .awaitingInput, level: evolutionStore.level),
                size: 22,
                form: evolutionStore.currentForm,
                level: evolutionStore.level,
                feedTrigger: feedTrigger
            )

            Divider()
                .frame(width: 1, height: 18)
                .overlay(Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.45))

            VStack(alignment: .leading, spacing: 1) {
                Text("等待您的回复")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.94, green: 0.27, blue: 0.27))
                    .lineLimit(1)

                AwaitReasonLabel(reason: eventBus.awaitReason)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ActivateCodexButton(title: "回复")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        .overlay(
            RoundedRectangle(cornerRadius: IslandShape.capsuleCornerRadius, style: .continuous)
                .stroke(
                    Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.56),
                    lineWidth: 1.5
                )
        )
        .onAppear {
            sendNotificationIfNeeded()
        }
        .onChange(of: eventBus.awaitReason) { _ in
            sendNotificationIfNeeded()
        }
        .onChange(of: eventBus.activeSessionId) { _ in
            sendNotificationIfNeeded()
        }
    }

    private func sendNotificationIfNeeded() {
        AwaitNotificationCoordinator.shared.notifyIfNeeded(
            sessionId: eventBus.activeSessionId,
            reason: eventBus.awaitReason
        )
    }
}
