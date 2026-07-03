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
        HStack(spacing: 7) {
            TokenPill(
                label: settings.text(.input),
                value: store.totalInput,
                color: TokenColors.input,
                width: 44
            )

            TokenPill(
                label: settings.text(.cached),
                value: store.totalCachedInput,
                color: TokenColors.cached,
                suffix: store.cacheHitPercent,
                width: 68
            )

            TokenPill(
                label: settings.text(.output),
                value: store.totalOutput,
                color: TokenColors.output,
                width: 44
            )

            TokenPill(
                label: todayLabel,
                value: store.todayTotalTokens,
                color: TokenColors.output,
                width: 52
            )

            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: 52,
                alignment: .trailing
            )
        }
        .frame(width: 296, height: 28)
    }

    private var todayLabel: String {
        switch settings.language {
        case .chinese:
            return "今日"
        case .english:
            return "TODAY"
        }
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
