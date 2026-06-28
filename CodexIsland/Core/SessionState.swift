import Foundation

enum CodexSessionState: String, Codable, Equatable {
    case idle
    case thinking
    case streaming
    case awaitingInput = "awaiting_input"
    case error
}

enum AwaitReason: Codable, Equatable {
    case toolApproval(tool: String, command: String?)
    case question(text: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case tool
        case command
        case text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "tool_approval":
            let tool = try container.decode(String.self, forKey: .tool)
            let command = try container.decodeIfPresent(String.self, forKey: .command)
            self = .toolApproval(tool: tool, command: command)
        default:
            let text = try container.decodeIfPresent(String.self, forKey: .text)
            self = .question(text: text)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .toolApproval(let tool, let command):
            try container.encode("tool_approval", forKey: .type)
            try container.encode(tool, forKey: .tool)
            try container.encodeIfPresent(command, forKey: .command)
        case .question(let text):
            try container.encode("question", forKey: .type)
            try container.encodeIfPresent(text, forKey: .text)
        }
    }
}

struct SessionStateEvent: Codable, Equatable {
    let sessionId: String
    let state: CodexSessionState
    let timestamp: Date
    let awaitReason: AwaitReason?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state
        case timestamp
        case awaitReason = "await_reason"
    }
}
