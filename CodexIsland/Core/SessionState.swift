import Foundation

enum CodexSessionState: String, Codable, Equatable {
    case notLoaded = "not_loaded"
    case idle
    case running
    case waitingForInput = "waiting_for_input"
    case readyForReview = "ready_for_review"
    case error
}

enum CodexActivityKind: String, Codable, Equatable {
    case none
    case reasoning
    case commandExecution = "command_execution"
    case fileChange = "file_change"
    case webSearch = "web_search"
    case agentMessage = "agent_message"
}

enum CodexTurnState: String, Codable, Equatable {
    case inProgress = "in_progress"
    case completed
    case interrupted
    case failed
}

enum SessionStateSource: String, Codable, Equatable {
    case appServer = "app_server"
    case jsonl
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
    let activityKind: CodexActivityKind
    let turnState: CodexTurnState?
    let source: SessionStateSource?
    let timestamp: Date
    let awaitReason: AwaitReason?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case state
        case activityKind = "activity_kind"
        case turnState = "turn_state"
        case source
        case timestamp
        case awaitReason = "await_reason"
    }

    init(
        sessionId: String,
        state: CodexSessionState,
        activityKind: CodexActivityKind = .none,
        turnState: CodexTurnState? = nil,
        source: SessionStateSource? = nil,
        timestamp: Date,
        awaitReason: AwaitReason? = nil
    ) {
        self.sessionId = sessionId
        self.state = state
        self.activityKind = activityKind
        self.turnState = turnState
        self.source = source
        self.timestamp = timestamp
        self.awaitReason = awaitReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        state = try container.decode(CodexSessionState.self, forKey: .state)
        activityKind = try container.decodeIfPresent(CodexActivityKind.self, forKey: .activityKind) ?? .none
        turnState = try container.decodeIfPresent(CodexTurnState.self, forKey: .turnState)
        source = try container.decodeIfPresent(SessionStateSource.self, forKey: .source)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        awaitReason = try container.decodeIfPresent(AwaitReason.self, forKey: .awaitReason)
    }
}
