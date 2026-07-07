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
        HStack(spacing: 8) {
            TokenPill(
                label: settings.text(.input),
                value: store.totalInput,
                color: TokenColors.input,
                width: largePillWidth
            )

            TokenPill(
                label: settings.text(.cached),
                value: store.totalCachedInput,
                color: TokenColors.cached,
                suffix: store.cacheHitPercent,
                width: largePillWidth
            )

            TokenPill(
                label: settings.text(.output),
                value: store.totalOutput,
                color: TokenColors.output,
                width: largePillWidth
            )

            TokenPill(
                label: todayLabel,
                value: store.todayTotalTokens,
                color: TokenColors.today,
                width: largePillWidth
            )

            TokenPill(
                label: contextLabel,
                value: store.contextUsedTokens,
                color: TokenColors.context,
                suffix: store.contextUsagePercent,
                width: largePillWidth
            )

            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: largePillWidth
            )
        }
        .frame(width: 304, height: 28)
    }

    private var largePillWidth: CGFloat { 44 }

    private var todayLabel: String {
        switch settings.language {
        case .chinese:
            return "今日"
        case .english:
            return "TODAY"
        }
    }

    private var contextLabel: String {
        switch settings.language {
        case .chinese:
            return "上下文"
        case .english:
            return "CTX"
        }
    }

    private var smallRow: some View {
        HStack(spacing: 4) {
            TokenPill(
                label: todayLabel,
                value: store.todayTotalTokens,
                color: TokenColors.today,
                width: 40
            )

            TokenPill(
                label: settings.text(.total),
                value: store.totalTokens,
                color: TokenColors.total,
                width: 48,
                alignment: .trailing
            )
        }
        .frame(width: 92, height: 28)
    }
}
