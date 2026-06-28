import Foundation

struct GlobalTokenUsageSnapshot: Codable {
    let type: String
    let totalInput: Int
    let totalCachedInput: Int
    let totalOutput: Int
    let totalReasoning: Int
    let totalTokens: Int
    let sessionCount: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case type
        case totalInput = "total_input"
        case totalCachedInput = "total_cached_input"
        case totalOutput = "total_output"
        case totalReasoning = "total_reasoning"
        case totalTokens = "total_tokens"
        case sessionCount = "session_count"
        case updatedAt = "updated_at"
    }
}
