import SwiftUI

struct AwaitingView: View {
    @ObservedObject private var eventBus = EventBus.shared

    var feedTrigger: UUID?

    @State private var borderOpacity = 0.18

    var body: some View {
        HStack(spacing: 8) {
            PixelPetView(
                animationName: .awaitJump,
                size: 22,
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
                    Color(red: 0.94, green: 0.27, blue: 0.27).opacity(borderOpacity),
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: Color(red: 0.94, green: 0.27, blue: 0.27).opacity(borderOpacity * 0.45),
            radius: 8
        )
        .onAppear {
            startBorderPulse()
            sendNotificationIfNeeded()
        }
        .onChange(of: eventBus.awaitReason) { _ in
            sendNotificationIfNeeded()
        }
        .onChange(of: eventBus.activeSessionId) { _ in
            sendNotificationIfNeeded()
        }
    }

    private func startBorderPulse() {
        borderOpacity = 0.18

        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            borderOpacity = 0.82
        }
    }

    private func sendNotificationIfNeeded() {
        AwaitNotificationCoordinator.shared.notifyIfNeeded(
            sessionId: eventBus.activeSessionId,
            reason: eventBus.awaitReason
        )
    }
}
