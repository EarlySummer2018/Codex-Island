import Combine
import Foundation

struct TokenSnapshot: Codable, Identifiable {
    let id = UUID()

    let sessionId: String
    let sessionFile: String

    let deltaInput: Int
    let deltaCachedInput: Int
    let deltaUncachedInput: Int
    let deltaOutput: Int
    let deltaReasoning: Int

    let totalInput: Int
    let totalCachedInput: Int
    let totalUncachedInput: Int
    let totalOutput: Int
    let totalReasoning: Int
    let contextUsed: Int?
    let contextWindow: Int?

    let cacheHitRate: Double
    let timestamp: Date
    let turnIndex: Int

    private static let defaultContextWindow = 258_400

    var cacheHitPercent: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }

    var contextUsagePercent: String {
        guard let contextUsed else {
            return "0.0%"
        }

        let window = contextWindow ?? Self.defaultContextWindow
        return String(format: "%.1f%%", Double(contextUsed) / Double(window) * 100)
    }

    var totalTokens: Int {
        totalInput + totalOutput
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case sessionFile = "session_file"
        case deltaInput = "delta_input"
        case deltaCachedInput = "delta_cached_input"
        case deltaUncachedInput = "delta_uncached_input"
        case deltaOutput = "delta_output"
        case deltaReasoning = "delta_reasoning"
        case totalInput = "total_input"
        case totalCachedInput = "total_cached_input"
        case totalUncachedInput = "total_uncached_input"
        case totalOutput = "total_output"
        case totalReasoning = "total_reasoning"
        case contextUsed = "context_used"
        case contextWindow = "context_window"
        case cacheHitRate = "cache_hit_rate"
        case timestamp
        case turnIndex = "turn_index"
    }
}

@MainActor
final class TokenStore: ObservableObject {
    static let shared = TokenStore()

    @Published private(set) var latest: TokenSnapshot?
    @Published private(set) var history: [TokenSnapshot] = []
    @Published private(set) var globalUsage: GlobalTokenUsageSnapshot?
    @Published private(set) var dailyUsage: DailyTokenUsageSnapshot?

    private var historiesBySession: [String: [TokenSnapshot]] = [:]
    private let maxStoredSessions = 32

    var totalInput: Int { latest?.totalInput ?? 0 }
    var totalCachedInput: Int { latest?.totalCachedInput ?? 0 }
    var totalUncachedInput: Int { latest?.totalUncachedInput ?? 0 }
    var totalOutput: Int { latest?.totalOutput ?? 0 }
    var totalTokens: Int { latest?.totalTokens ?? 0 }
    var todayTotalTokens: Int { dailyUsage?.totalTokens ?? 0 }
    var todayRequestCount: Int { dailyUsage?.requestCount ?? 0 }
    var globalTotalInput: Int { globalUsage?.totalInput ?? 0 }
    var globalTotalCachedInput: Int { globalUsage?.totalCachedInput ?? 0 }
    var globalTotalOutput: Int { globalUsage?.totalOutput ?? 0 }
    var globalTotalTokens: Int { globalUsage?.totalTokens ?? 0 }
    var globalCacheHitRate: Double {
        guard globalTotalInput > 0 else {
            return 0
        }
        return Double(globalTotalCachedInput) / Double(globalTotalInput)
    }
    var globalCacheHitPercent: String {
        String(format: "%.1f%%", globalCacheHitRate * 100)
    }
    var contextUsedTokens: Int { latest?.contextUsed ?? 0 }
    var contextUsagePercent: String { latest?.contextUsagePercent ?? "0.0%" }
    var cacheHitPercent: String { latest?.cacheHitPercent ?? "0.0%" }

    func update(with snapshot: TokenSnapshot, isActive: Bool = true) {
        var sessionHistory = historiesBySession[snapshot.sessionId, default: []]
        sessionHistory.append(snapshot)

        if sessionHistory.count > 100 {
            sessionHistory.removeFirst(sessionHistory.count - 100)
        }

        historiesBySession[snapshot.sessionId] = sessionHistory
        pruneStoredSessions()

        if isActive {
            latest = snapshot
            history = sessionHistory
        }
    }

    func update(with snapshot: DailyTokenUsageSnapshot) {
        dailyUsage = snapshot
    }

    func update(with snapshot: GlobalTokenUsageSnapshot) {
        globalUsage = snapshot
    }

    func showSession(_ sessionId: String, latest snapshot: TokenSnapshot?) {
        latest = snapshot ?? historiesBySession[sessionId]?.last
        history = historiesBySession[sessionId] ?? []
    }

    func reset() {
        latest = nil
        history.removeAll()
        historiesBySession.removeAll()
        globalUsage = nil
        dailyUsage = nil
    }

    private func pruneStoredSessions() {
        guard historiesBySession.count > maxStoredSessions else {
            return
        }

        let removable = historiesBySession
            .map { item in
                (sessionId: item.key, lastDate: item.value.last?.timestamp ?? .distantPast)
            }
            .sorted { lhs, rhs in
                lhs.lastDate < rhs.lastDate
            }
            .prefix(historiesBySession.count - maxStoredSessions)

        for item in removable {
            historiesBySession.removeValue(forKey: item.sessionId)
        }
    }
}
