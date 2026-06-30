import Combine
import Foundation

enum PetForm: String, CaseIterable, Codable {
    case core
    case antenna
    case ripple
    case shell
    case spark
    case glider
    case shield
    case crystal
    case star
    case spirit

    var assetName: String {
        switch self {
        case .core:
            return "codex_core"
        case .antenna:
            return "codex_core_antenna"
        case .ripple:
            return "codex_core_ripple"
        case .shell:
            return "codex_core_shell"
        case .spark:
            return "codex_core_spark"
        case .glider:
            return "codex_core_glider"
        case .shield:
            return "codex_core_shield"
        case .crystal:
            return "codex_core_crystal"
        case .star:
            return "codex_core_star"
        case .spirit:
            return "codex_core_spirit"
        }
    }

    var unlockLevel: Int {
        switch self {
        case .core:
            return 0
        case .antenna:
            return 10
        case .ripple:
            return 20
        case .shell:
            return 30
        case .spark:
            return 40
        case .glider:
            return 50
        case .shield:
            return 60
        case .crystal:
            return 70
        case .star:
            return 80
        case .spirit:
            return 90
        }
    }

    var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func form(for level: Int) -> PetForm {
        let clampedLevel = PetLevelCurve.clamp(level)
        return Self.allCases
            .last { clampedLevel >= $0.unlockLevel } ?? .core
    }
}

enum PetLevelCurve {
    static let maxLevel = 100
    static let tokensPerLevelSquared: Int64 = 10_950_000

    static func clamp(_ level: Int) -> Int {
        min(max(level, 0), maxLevel)
    }

    static func tokensRequired(for level: Int) -> Int64 {
        let clampedLevel = Int64(clamp(level))
        return tokensPerLevelSquared * clampedLevel * clampedLevel
    }

    static func level(for earnedTokens: Int64) -> Int {
        let tokens = max(earnedTokens, 0)

        for level in stride(from: maxLevel, through: 0, by: -1) {
            if tokens >= tokensRequired(for: level) {
                return level
            }
        }

        return 0
    }

    static func progress(for earnedTokens: Int64) -> Double {
        let currentLevel = level(for: earnedTokens)
        guard currentLevel < maxLevel else {
            return 1
        }

        let start = tokensRequired(for: currentLevel)
        let target = tokensRequired(for: currentLevel + 1)
        guard target > start else {
            return 1
        }

        let progress = Double(max(earnedTokens, 0) - start) / Double(target - start)
        return min(max(progress, 0), 1)
    }

    static func tokensToNextLevel(for earnedTokens: Int64) -> Int64? {
        let currentLevel = level(for: earnedTokens)
        guard currentLevel < maxLevel else {
            return nil
        }

        return max(tokensRequired(for: currentLevel + 1) - max(earnedTokens, 0), 0)
    }
}

@MainActor
final class PetEvolutionStore: ObservableObject {
    static let shared = PetEvolutionStore()

    @Published private(set) var globalUsage: GlobalTokenUsageSnapshot?
    @Published private(set) var level = 0
    @Published private(set) var earnedTokens: Int64 = 0
    @Published private(set) var currentForm: PetForm = .core
    @Published private(set) var levelProgress: Double = 0
    @Published private(set) var tokensToNextLevel: Int64? = PetLevelCurve.tokensRequired(for: 1)
    @Published private(set) var feedTrigger: UUID?
    @Published private(set) var levelUpTrigger: UUID?

    private let defaults: UserDefaults
    private let feedMilestoneSize: Int64 = 25_000_000
    private let earnedTokensKey = "CodexIsland.PetEvolutionV2.earnedTokens"
    private let lastObservedTotalTokensKey = "CodexIsland.PetEvolutionV2.lastObservedTotalTokens"
    private let lastFeedMilestoneKey = "CodexIsland.PetEvolutionV2.lastFeedMilestone"
    private let historicalTokensImportedKey = "CodexIsland.PetEvolutionV2.historicalTokensImported"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        earnedTokens = Self.int64(forKey: earnedTokensKey, defaults: defaults)
        refreshProgress()
    }

    func update(with snapshot: GlobalTokenUsageSnapshot) {
        globalUsage = snapshot

        let snapshotTotal = max(Int64(snapshot.totalTokens), 0)

        guard defaults.bool(forKey: historicalTokensImportedKey) else {
            importHistoricalTokens(snapshotTotal)
            return
        }

        let lastObserved = Self.optionalInt64(forKey: lastObservedTotalTokensKey, defaults: defaults) ?? snapshotTotal
        let previousLevel = level
        let delta = max(snapshotTotal - lastObserved, 0)
        let nextLastObserved = max(lastObserved, snapshotTotal)

        if delta > 0 {
            earnedTokens += delta
            defaults.set(earnedTokens, forKey: earnedTokensKey)
        }

        defaults.set(nextLastObserved, forKey: lastObservedTotalTokensKey)
        refreshProgress()

        if level > previousLevel {
            levelUpTrigger = UUID()
        }

        let nextFeedMilestone = earnedTokens / feedMilestoneSize
        let lastFeedMilestone = Self.int64(forKey: lastFeedMilestoneKey, defaults: defaults)
        if nextFeedMilestone > lastFeedMilestone {
            defaults.set(nextFeedMilestone, forKey: lastFeedMilestoneKey)
            feedTrigger = UUID()
        }
    }

    private func importHistoricalTokens(_ snapshotTotal: Int64) {
        earnedTokens = max(earnedTokens, snapshotTotal)
        defaults.set(earnedTokens, forKey: earnedTokensKey)
        defaults.set(snapshotTotal, forKey: lastObservedTotalTokensKey)
        defaults.set(earnedTokens / feedMilestoneSize, forKey: lastFeedMilestoneKey)
        defaults.set(true, forKey: historicalTokensImportedKey)
        refreshProgress()
    }

    private func refreshProgress() {
        level = PetLevelCurve.level(for: earnedTokens)
        currentForm = PetForm.form(for: level)
        levelProgress = PetLevelCurve.progress(for: earnedTokens)
        tokensToNextLevel = PetLevelCurve.tokensToNextLevel(for: earnedTokens)
    }

    private static func optionalInt64(forKey key: String, defaults: UserDefaults) -> Int64? {
        guard let value = defaults.object(forKey: key) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.int64Value
        }

        return value as? Int64
    }

    private static func int64(forKey key: String, defaults: UserDefaults) -> Int64 {
        optionalInt64(forKey: key, defaults: defaults) ?? 0
    }
}
