import SwiftUI

struct TokenInfoRow: View {
    @ObservedObject private var store = TokenStore.shared
    @ObservedObject private var settings = AppSettingsStore.shared
    var style: CapsuleDisplayStyle = .large

    var body: some View {
        switch style {
        case .large:
            largeRow
        case .small:
            smallRow
        }
    }

    private var largeRow: some View {
        HStack(spacing: 4) {
            petSlot

            TokenPill(
                label: settings.text(.input),
                value: store.totalInput,
                color: TokenColors.input,
                width: 54
            )

            petSlot

            TokenPill(
                label: settings.text(.cached),
                value: store.totalCachedInput,
                color: TokenColors.cached,
                suffix: store.cacheHitPercent,
                width: 82
            )

            petSlot

            TokenPill(
                label: settings.text(.output),
                value: store.totalOutput,
                color: TokenColors.output,
                width: 54
            )

            petSlot

            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: 64,
                alignment: .trailing
            )

            petSlot
        }
        .frame(width: 416, height: 28)
    }

    private var smallRow: some View {
        HStack(spacing: 4) {
            Color.clear
                .frame(width: 34, height: 28)

            Spacer(minLength: 0)

            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: 92,
                alignment: .trailing
            )

            Color.clear
                .frame(width: 34, height: 28)
        }
        .frame(width: 236, height: 28)
    }

    private var petSlot: some View {
        Color.clear
            .frame(width: 26, height: 28)
    }
}
