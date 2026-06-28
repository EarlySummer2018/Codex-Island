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

    let cacheHitRate: Double
    let timestamp: Date
    let turnIndex: Int

    var cacheHitPercent: String {
        String(format: "%.1f%%", cacheHitRate * 100)
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

    private var historiesBySession: [String: [TokenSnapshot]] = [:]

    var totalInput: Int { latest?.totalInput ?? 0 }
    var totalCachedInput: Int { latest?.totalCachedInput ?? 0 }
    var totalUncachedInput: Int { latest?.totalUncachedInput ?? 0 }
    var totalOutput: Int { latest?.totalOutput ?? 0 }
    var totalTokens: Int { latest?.totalTokens ?? 0 }
    var cacheHitPercent: String { latest?.cacheHitPercent ?? "0.0%" }

    func update(with snapshot: TokenSnapshot, isActive: Bool = true) {
        var sessionHistory = historiesBySession[snapshot.sessionId, default: []]
        sessionHistory.append(snapshot)

        if sessionHistory.count > 100 {
            sessionHistory.removeFirst(sessionHistory.count - 100)
        }

        historiesBySession[snapshot.sessionId] = sessionHistory

        if isActive {
            latest = snapshot
            history = sessionHistory
        }
    }

    func showSession(_ sessionId: String, latest snapshot: TokenSnapshot?) {
        latest = snapshot ?? historiesBySession[sessionId]?.last
        history = historiesBySession[sessionId] ?? []
    }

    func reset() {
        latest = nil
        history.removeAll()
        historiesBySession.removeAll()
    }
}
