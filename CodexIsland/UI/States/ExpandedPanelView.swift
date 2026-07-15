import SwiftUI

struct ExpandedPanelView: View {
    @ObservedObject private var store = TokenStore.shared
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared
    @ObservedObject private var settings = AppSettingsStore.shared
    var onSettingsTapped: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header

            neonDivider

            if eventBus.isAwaitingInput {
                AwaitingDetailPanel(reason: eventBus.awaitReason)
                    .padding(.horizontal, PanelMetrics.horizontalPadding)
                    .padding(.vertical, PanelMetrics.contentTopPadding)

                neonDivider
            }

            VStack(spacing: 0) {
                mainDeck

                tokenGrid
                    .padding(.top, PanelMetrics.mainToTokenGap)

                footer
                    .padding(.top, PanelMetrics.footerTopPadding)
                    .padding(.bottom, PanelMetrics.footerBottomPadding)
            }
            .padding(.horizontal, PanelMetrics.horizontalPadding)
            .padding(.top, PanelMetrics.contentTopPadding)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(PanelPalette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PanelPalette.magenta.opacity(0.45), lineWidth: 1)
                    )

                PixelPetView(
                    animationName: PetAnimation.from(
                        state: eventBus.sessionState,
                        activityKind: eventBus.activityKind,
                        level: evolutionStore.level
                    ),
                    size: 30,
                    form: evolutionStore.currentForm,
                    level: evolutionStore.level,
                    feedTrigger: evolutionStore.feedTrigger
                )
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: eventBus.sessionState))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let activityText {
                    Text(activityText)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(PanelPalette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(levelLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(PanelPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 28)

                settingsButton
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(PanelPalette.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(PanelPalette.magenta.opacity(0.20), lineWidth: 1)
            )
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .frame(height: 64)
    }

    private var settingsButton: some View {
        Button(action: onSettingsTapped) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PanelPalette.text)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(settingsTitle)
        .help(settingsTitle)
    }

    private var mainDeck: some View {
        HStack(spacing: PanelMetrics.mainDeckGap) {
            petShowcase

            evolutionConsole
        }
    }

    private var petShowcase: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 4)

                PixelPetView(
                    animationName: PetAnimation.from(
                        state: eventBus.sessionState,
                        activityKind: eventBus.activityKind,
                        level: evolutionStore.level
                    ),
                    size: 82,
                    form: evolutionStore.currentForm,
                    level: evolutionStore.level,
                feedTrigger: evolutionStore.feedTrigger
            )

            HStack(spacing: 8) {
                MetricChip(title: "LV", value: "\(evolutionStore.level)", color: PanelPalette.magenta)
                MetricChip(title: "C", value: store.globalCacheHitPercent, color: PanelPalette.cyan)
            }

            Spacer(minLength: 8)
        }
        .padding(8)
        .frame(width: PanelMetrics.petColumnWidth, height: PanelMetrics.mainDeckHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PanelPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PanelPalette.edge, lineWidth: 1)
        )
    }

    private var evolutionConsole: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(evolutionTitle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelPalette.text)

                Spacer(minLength: 0)

                Text(evolutionPercentText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            NeonProgressBar(progress: evolutionProgress)
                .frame(height: 7)

            HStack {
                Text(consumedText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 0)

                Text(nextTokenText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(spacing: 6) {
                ConsoleStat(title: turnTitle, value: turnText, color: PanelPalette.cyan)
                ConsoleStat(title: todayTitle, value: TokenFormatter.format(store.todayTotalTokens), color: TokenColors.output)
                ConsoleStat(title: totalTitle, value: TokenFormatter.format(store.globalTotalTokens), color: PanelPalette.magenta)
            }

            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(primaryStatText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white)
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: PanelMetrics.mainDeckHeight, maxHeight: PanelMetrics.mainDeckHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PanelPalette.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PanelPalette.edge, lineWidth: 1)
        )
    }

    private var tokenGrid: some View {
        HStack(spacing: 8) {
            ForEach(ExpandedTokenCardMetric.displayOrder, id: \.self) { metric in
                tokenCard(for: metric)
            }
        }
        .frame(height: 56)
    }

    @ViewBuilder
    private func tokenCard(for metric: ExpandedTokenCardMetric) -> some View {
        switch metric {
        case .input:
            TokenCard(
                title: settings.text(.input),
                value: store.globalTotalInput,
                color: TokenColors.input
            )
        case .output:
            TokenCard(
                title: settings.text(.output),
                value: store.globalTotalOutput,
                color: TokenColors.output
            )
        case .cached:
            TokenCard(
                title: settings.text(.cached),
                value: store.globalTotalCachedInput,
                color: TokenColors.cached
            )
        case .cacheRate:
            TokenCard(
                title: settings.text(.cacheRate),
                text: store.globalCacheHitPercent,
                color: TokenColors.uncached
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            Text(footerText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)

            Text(versionText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.textDim)
                .lineLimit(1)
        }
        .frame(height: 20)
    }

    private var evolutionProgress: Double {
        evolutionStore.levelProgress
    }

    private var evolutionPercentText: String {
        "\(Int((evolutionProgress * 100).rounded()))%"
    }

    private var nextTokenText: String {
        guard let tokensToNext = evolutionStore.tokensToNextLevel else {
            return maxProgressText
        }

        switch settings.language {
        case .chinese:
            return "距 Lv.\(evolutionStore.level + 1) \(TokenFormatter.format(tokensToNext))"
        case .english:
            return "\(TokenFormatter.format(tokensToNext)) to Lv.\(evolutionStore.level + 1)"
        }
    }

    private var evolutionTitle: String {
        switch settings.language {
        case .chinese:
            return "等级经验"
        case .english:
            return "Level Exp"
        }
    }

    private var consumedText: String {
        let value = TokenFormatter.format(evolutionStore.earnedTokens)

        switch settings.language {
        case .chinese:
            return "成长累计 \(value)"
        case .english:
            return "\(value) growth tokens"
        }
    }

    private var maxProgressText: String {
        switch settings.language {
        case .chinese:
            return "已满"
        case .english:
            return "MAX"
        }
    }

    private var turnTitle: String {
        switch settings.language {
        case .chinese:
            return "轮次"
        case .english:
            return "TURN"
        }
    }

    private var totalTitle: String {
        switch settings.language {
        case .chinese:
            return settings.text(.total)
        case .english:
            return "ALL"
        }
    }

    private var todayTitle: String {
        switch settings.language {
        case .chinese:
            return "今日"
        case .english:
            return "TODAY"
        }
    }

    private var levelLabel: String {
        "Lv.\(evolutionStore.level)"
    }

    private var settingsTitle: String {
        switch settings.language {
        case .chinese:
            return "设置"
        case .english:
            return "Settings"
        }
    }

    private var turnText: String {
        "\(store.todayRequestCount)"
    }

    private var primaryStatText: String {
        guard evolutionStore.level < PetLevelCurve.maxLevel else {
            return maxProgressText
        }

        let nextLevel = evolutionStore.level + 1
        let required = PetLevelCurve.tokensRequired(for: nextLevel)
        let tokenText = TokenFormatter.format(required)

        switch settings.language {
        case .chinese:
            return "升 Lv.\(nextLevel) · 总经验 \(tokenText)"
        case .english:
            return "Lv.\(nextLevel) · \(tokenText) total XP"
        }
    }

    private var footerText: String {
        if let activityText = activityText {
            return "\(title(for: eventBus.sessionState)) · \(activityText)"
        }

        return title(for: eventBus.sessionState)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "v\(version)"
    }

    private var statusColor: Color {
        switch eventBus.sessionState {
        case .notLoaded:
            return PanelPalette.textMuted
        case .idle:
            return PanelPalette.textMuted
        case .running:
            return PanelPalette.cyan
        case .waitingForInput:
            return Color(red: 0.94, green: 0.27, blue: 0.27)
        case .readyForReview:
            return PanelPalette.magenta
        case .error:
            return Color(red: 1.0, green: 0.18, blue: 0.18)
        }
    }

    private var neonDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        PanelPalette.magenta.opacity(0.30),
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private func title(for state: CodexSessionState) -> String {
        switch state {
        case .notLoaded:
            return settings.text(.notLoaded)
        case .idle:
            return settings.text(.idle)
        case .running:
            return settings.text(.running)
        case .waitingForInput:
            return settings.text(.waitingForInput)
        case .readyForReview:
            return settings.text(.readyForReview)
        case .error:
            return settings.text(.error)
        }
    }

    private var activityText: String? {
        switch eventBus.activityKind {
        case .none:
            return nil
        case .reasoning:
            return settings.text(.reasoning)
        case .commandExecution:
            return settings.text(.commandExecution)
        case .fileChange:
            return settings.text(.fileChange)
        case .webSearch:
            return settings.text(.webSearch)
        case .agentMessage:
            return settings.text(.agentMessage)
        }
    }
}

enum PanelMetrics {
    static let horizontalPadding: CGFloat = 14
    static let contentTopPadding: CGFloat = 8
    static let mainDeckHeight: CGFloat = 122
    static let mainDeckGap: CGFloat = 8
    static let mainToTokenGap: CGFloat = 8
    static let footerTopPadding: CGFloat = 4
    static let footerBottomPadding: CGFloat = 6
    static let petColumnWidth: CGFloat = 132
}

enum PanelPalette {
    static let surface = Color(red: 0.035, green: 0.035, blue: 0.045)
    static let control = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let edge = Color.white.opacity(0.08)
    static let magenta = Color(red: 1.0, green: 0.20, blue: 0.56)
    static let purple = Color(red: 0.52, green: 0.25, blue: 0.95)
    static let cyan = Color(red: 0.28, green: 0.88, blue: 0.78)
    static let text = Color.white.opacity(0.90)
    static let textMuted = Color.white.opacity(0.68)
    static let textDim = Color.white.opacity(0.50)
}

enum ExpandedTokenCardMetric: Hashable {
    case input
    case output
    case cached
    case cacheRate

    static let displayOrder: [ExpandedTokenCardMetric] = [
        .input,
        .output,
        .cached,
        .cacheRate
    ]
}

private struct MetricChip: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        Text("\(title)=\(value)")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(color.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color.opacity(0.22), lineWidth: 1)
            )
    }
}

private struct ConsoleStat: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(PanelPalette.textDim)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(PanelPalette.control.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(color.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct NeonProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let clampedProgress = min(max(progress, 0), 1)
            let progressWidth = max(proxy.size.width * clampedProgress, clampedProgress > 0 ? 4 : 0)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [PanelPalette.magenta, PanelPalette.purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: progressWidth)
            }
        }
    }
}
