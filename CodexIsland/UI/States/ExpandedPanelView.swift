import SwiftUI

struct ExpandedPanelView: View {
    @ObservedObject private var store = TokenStore.shared
    @ObservedObject private var eventBus = EventBus.shared
    @ObservedObject private var evolutionStore = PetEvolutionStore.shared
    @ObservedObject private var settings = AppSettingsStore.shared

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
                    animationName: PetAnimation.from(state: eventBus.sessionState),
                    size: 30,
                    stage: evolutionStore.stage,
                    prestigeLevel: evolutionStore.prestigeLevel,
                    feedTrigger: evolutionStore.feedTrigger,
                    evolutionTrigger: evolutionStore.evolutionTrigger
                )
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: eventBus.sessionState))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelPalette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(stageLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(PanelPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(minWidth: 28)

                dragHandle
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
            .help(dragHelpText)
        }
        .padding(.horizontal, PanelMetrics.horizontalPadding)
        .frame(height: 64)
    }

    private var dragHandle: some View {
        VStack(spacing: 2) {
            Capsule()
                .fill(PanelPalette.textMuted)
                .frame(width: 16, height: 2)
            Capsule()
                .fill(PanelPalette.textDim)
                .frame(width: 16, height: 2)
            Capsule()
                .fill(PanelPalette.textDim)
                .frame(width: 16, height: 2)
        }
        .frame(width: 18, height: 16)
        .accessibilityLabel(dragHelpText)
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
                animationName: PetAnimation.from(state: eventBus.sessionState),
                size: 82,
                stage: evolutionStore.stage,
                prestigeLevel: evolutionStore.prestigeLevel,
                feedTrigger: evolutionStore.feedTrigger,
                evolutionTrigger: evolutionStore.evolutionTrigger
            )

            HStack(spacing: 8) {
                MetricChip(title: "E", value: evolutionPercentText, color: PanelPalette.magenta)
                MetricChip(title: "C", value: store.cacheHitPercent, color: PanelPalette.cyan)
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
                ConsoleStat(title: outputTitle, value: TokenFormatter.format(store.totalOutput), color: TokenColors.output)
                ConsoleStat(title: totalTitle, value: TokenFormatter.format(store.totalTokens), color: PanelPalette.magenta)
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
        .frame(height: 56)
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

            Text(cacheSummary)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.text)
                .lineLimit(1)

            Text(versionText)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelPalette.textDim)
                .lineLimit(1)
        }
        .frame(height: 20)
    }

    private var subtitle: String {
        guard let token = store.latest else {
            return settings.text(.noTokenDataYet)
        }

        return "\(settings.text(.sessionTotalPrefix))\(TokenFormatter.format(token.totalTokens))\(settings.text(.sessionTotalSuffix))"
    }

    private var globalTotal: Int {
        evolutionStore.globalUsage?.totalTokens ?? store.totalTokens
    }

    private var currentStageIndex: Int {
        PetEvolutionStage.allCases.firstIndex(of: evolutionStore.stage) ?? 0
    }

    private var nextStage: PetEvolutionStage? {
        let nextIndex = currentStageIndex + 1
        guard PetEvolutionStage.allCases.indices.contains(nextIndex) else {
            return nil
        }

        return PetEvolutionStage.allCases[nextIndex]
    }

    private var evolutionProgress: Double {
        guard let nextStage else {
            return 1
        }

        let start = evolutionStore.stage.threshold
        let target = nextStage.threshold
        guard target > start else {
            return 1
        }

        let progress = Double(globalTotal - start) / Double(target - start)
        return min(max(progress, 0), 1)
    }

    private var evolutionPercentText: String {
        "\(Int((evolutionProgress * 100).rounded()))%"
    }

    private var nextTokenText: String {
        guard let nextStage else {
            return maxProgressText
        }

        return "\(TokenFormatter.format(nextStage.threshold)) tokens"
    }

    private var evolutionTitle: String {
        switch settings.language {
        case .chinese:
            return "进化经验"
        case .english:
            return "Evolution Exp"
        }
    }

    private var consumedText: String {
        let value = TokenFormatter.format(globalTotal)

        switch settings.language {
        case .chinese:
            return "已消耗 \(value)"
        case .english:
            return "\(value) consumed"
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

    private var outputTitle: String {
        switch settings.language {
        case .chinese:
            return settings.text(.output)
        case .english:
            return "OUT"
        }
    }

    private var stageLabel: String {
        switch settings.language {
        case .chinese:
            switch evolutionStore.stage {
            case .egg:
                return "蛋"
            case .hatchling:
                return "幼体"
            case .sproutDrake:
                return "幼龙"
            case .glider:
                return "飞龙"
            case .guardian:
                return "守卫"
            case .ancient:
                return "古龙"
            }
        case .english:
            switch evolutionStore.stage {
            case .egg:
                return "EGG"
            case .hatchling:
                return "HATCH"
            case .sproutDrake:
                return "DRAKE"
            case .glider:
                return "GLIDE"
            case .guardian:
                return "GUARD"
            case .ancient:
                return "ANCIENT"
            }
        }
    }

    private var dragHelpText: String {
        switch settings.language {
        case .chinese:
            return "按住此区域拖拽"
        case .english:
            return "Hold here to drag"
        }
    }

    private var turnText: String {
        guard let turn = store.latest?.turnIndex else {
            return "0"
        }

        return "\(turn)"
    }

    private var primaryStatText: String {
        let tokenText = TokenFormatter.format(max(globalTotal, store.totalTokens))
        return "\(tokenText) tokens"
    }

    private var footerText: String {
        if eventBus.isAwaitingInput {
            return title(for: .awaitingInput)
        }

        return title(for: eventBus.sessionState)
    }

    private var cacheSummary: String {
        "\(settings.text(.cached)) \(store.cacheHitPercent)"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "v\(version)"
    }

    private var statusColor: Color {
        switch eventBus.sessionState {
        case .idle:
            return PanelPalette.textMuted
        case .thinking:
            return TokenColors.uncached
        case .working:
            return TokenColors.uncached
        case .streaming:
            return PanelPalette.cyan
        case .awaitingInput:
            return Color(red: 0.94, green: 0.27, blue: 0.27)
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
        case .idle:
            return settings.text(.idle)
        case .thinking:
            return settings.text(.thinking)
        case .working:
            return settings.text(.working)
        case .streaming:
            return settings.text(.streaming)
        case .awaitingInput:
            return settings.text(.awaitingInput)
        case .error:
            return settings.text(.error)
        }
    }
}

private enum PanelMetrics {
    static let horizontalPadding: CGFloat = 14
    static let contentTopPadding: CGFloat = 8
    static let mainDeckHeight: CGFloat = 122
    static let mainDeckGap: CGFloat = 8
    static let mainToTokenGap: CGFloat = 8
    static let footerTopPadding: CGFloat = 4
    static let footerBottomPadding: CGFloat = 6
    static let petColumnWidth: CGFloat = 132
}

private enum PanelPalette {
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
