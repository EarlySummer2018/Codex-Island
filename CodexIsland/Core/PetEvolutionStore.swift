import Combine
import Foundation

enum PetEvolutionStage: String, CaseIterable, Codable {
    case egg
    case hatchling
    case sproutDrake
    case glider
    case guardian
    case ancient

    var threshold: Int {
        switch self {
        case .egg:
            return 0
        case .hatchling:
            return 50_000_000
        case .sproutDrake:
            return 250_000_000
        case .glider:
            return 1_000_000_000
        case .guardian:
            return 5_000_000_000
        case .ancient:
            return 20_000_000_000
        }
    }

    var assetName: String {
        switch self {
        case .egg:
            return "egg"
        case .hatchling:
            return "hatchling"
        case .sproutDrake:
            return "sprout_drake"
        case .glider:
            return "glider"
        case .guardian:
            return "guardian"
        case .ancient:
            return "ancient"
        }
    }

    var rank: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    static func stage(for totalTokens: Int) -> PetEvolutionStage {
        Self.allCases
            .last { totalTokens >= $0.threshold } ?? .egg
    }
}

@MainActor
final class PetEvolutionStore: ObservableObject {
    static let shared = PetEvolutionStore()

    @Published private(set) var globalUsage: GlobalTokenUsageSnapshot?
    @Published private(set) var stage: PetEvolutionStage = .egg
    @Published private(set) var prestigeLevel = 0
    @Published private(set) var feedTrigger: UUID?
    @Published private(set) var evolutionTrigger: UUID?

    private let defaults = UserDefaults.standard
    private let feedMilestoneSize = 10_000_000
    private let prestigeMilestoneSize = 20_000_000_000
    private let unlockedStageRankKey = "CodexIsland.PetEvolution.unlockedStageRank"
    private let unlockedPrestigeKey = "CodexIsland.PetEvolution.unlockedPrestige"
    private let lastFeedMilestoneKey = "CodexIsland.PetEvolution.lastFeedMilestone"
    private var hasReceivedSnapshot = false

    private init() {
        let savedRank = defaults.object(forKey: unlockedStageRankKey) as? Int ?? 0
        stage = PetEvolutionStage.allCases[safe: savedRank] ?? .egg
        prestigeLevel = defaults.integer(forKey: unlockedPrestigeKey)
    }

    func update(with snapshot: GlobalTokenUsageSnapshot) {
        globalUsage = snapshot

        let nextStage = PetEvolutionStage.stage(for: snapshot.totalTokens)
        let nextPrestige = prestigeLevel(for: snapshot.totalTokens)
        let nextFeedMilestone = snapshot.totalTokens / feedMilestoneSize

        if !hasReceivedSnapshot {
            hasReceivedSnapshot = true
            stage = nextStage
            prestigeLevel = nextPrestige
            saveProgress(stage: nextStage, prestige: nextPrestige)
            let savedFeedMilestone = defaults.object(forKey: lastFeedMilestoneKey) as? Int ?? 0
            defaults.set(max(savedFeedMilestone, nextFeedMilestone), forKey: lastFeedMilestoneKey)
            return
        }

        if nextStage.rank > stage.rank || nextPrestige > prestigeLevel {
            stage = nextStage
            prestigeLevel = nextPrestige
            saveProgress(stage: nextStage, prestige: nextPrestige)
            evolutionTrigger = UUID()
        } else {
            stage = nextStage
            prestigeLevel = nextPrestige
        }

        let lastFeedMilestone = defaults.integer(forKey: lastFeedMilestoneKey)
        if nextFeedMilestone > lastFeedMilestone {
            defaults.set(nextFeedMilestone, forKey: lastFeedMilestoneKey)
            feedTrigger = UUID()
        }
    }

    private func prestigeLevel(for totalTokens: Int) -> Int {
        guard totalTokens > PetEvolutionStage.ancient.threshold else {
            return 0
        }

        return (totalTokens - PetEvolutionStage.ancient.threshold) / prestigeMilestoneSize
    }

    private func saveProgress(stage: PetEvolutionStage, prestige: Int) {
        defaults.set(stage.rank, forKey: unlockedStageRankKey)
        defaults.set(prestige, forKey: unlockedPrestigeKey)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else {
            return nil
        }

        return self[index]
    }
}
