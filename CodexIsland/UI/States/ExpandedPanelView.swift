import SwiftUI

struct ExpandedPanelView: View {
    @ObservedObject private var store = TokenStore.shared
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared
    @ObservedObject private var settings = AppSettingsStore.shared

    var feedTrigger: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.10))

            if eventBus.isAwaitingInput {
                AwaitingDetailPanel(reason: eventBus.awaitReason)

                Divider()
                    .overlay(Color.white.opacity(0.10))
            }

            tokenGrid
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if store.history.count > 1 {
                Divider()
                    .overlay(Color.white.opacity(0.10))

                TokenHistoryChart(history: store.history)
                    .frame(height: 78)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PixelPetView(
                animationName: PetAnimation.from(state: eventBus.sessionState),
                size: 42,
                stage: evolutionStore.stage,
                prestigeLevel: evolutionStore.prestigeLevel,
                feedTrigger: evolutionStore.feedTrigger,
                evolutionTrigger: evolutionStore.evolutionTrigger
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: eventBus.sessionState))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private var tokenGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            TokenCard(title: settings.text(.input), value: store.totalInput, color: TokenColors.input)
            TokenCard(
                title: settings.text(.cached),
                value: store.totalCachedInput,
                color: TokenColors.cached,
                note: store.cacheHitPercent
            )
            TokenCard(title: settings.text(.uncached), value: store.totalUncachedInput, color: TokenColors.uncached)
            TokenCard(title: settings.text(.output), value: store.totalOutput, color: TokenColors.output)
        }
    }

    private var subtitle: String {
        guard let token = store.latest else {
            return settings.text(.noTokenDataYet)
        }

        return "\(settings.text(.sessionTotalPrefix))\(TokenFormatter.format(token.totalTokens))\(settings.text(.sessionTotalSuffix))"
    }

    private func title(for state: CodexSessionState) -> String {
        switch state {
        case .idle:
            return settings.text(.idle)
        case .thinking:
            return settings.text(.thinking)
        case .streaming:
            return settings.text(.streaming)
        case .awaitingInput:
            return settings.text(.awaitingInput)
        case .error:
            return settings.text(.error)
        }
    }
}
