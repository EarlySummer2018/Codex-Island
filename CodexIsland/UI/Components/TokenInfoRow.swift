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
        HStack(spacing: 12) {
            TokenPill(
                label: settings.text(.input),
                value: store.totalInput,
                color: TokenColors.input,
                width: 50
            )

            TokenPill(
                label: settings.text(.cached),
                value: store.totalCachedInput,
                color: TokenColors.cached,
                suffix: store.cacheHitPercent,
                width: 74
            )

            TokenPill(
                label: settings.text(.output),
                value: store.totalOutput,
                color: TokenColors.output,
                width: 50
            )

            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: 64,
                alignment: .trailing
            )
        }
        .frame(width: 296, height: 28)
    }

    private var smallRow: some View {
        HStack {
            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: 132,
                alignment: .trailing
            )
        }
        .frame(width: 132, height: 28)
    }
}
