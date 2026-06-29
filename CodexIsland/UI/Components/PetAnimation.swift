import Foundation

enum PetAnimation: String, Equatable {
    case idleBreathe = "idle_breathe"
    case idleStretch = "idle_stretch"
    case thinkSweat = "think_sweat"
    case talkWalk = "talk_walk"
    case awaitJump = "await_jump"
    case errorFall = "error_fall"
    case eatToken = "eat_token"
    case evolveGlow = "evolve_glow"

    var frameCount: Int {
        switch self {
        case .idleBreathe:
            return 8
        case .idleStretch:
            return 12
        case .thinkSweat:
            return 8
        case .talkWalk:
            return 8
        case .awaitJump:
            return 10
        case .errorFall:
            return 10
        case .eatToken, .evolveGlow:
            return 8
        }
    }

    var fps: Int {
        switch self {
        case .awaitJump:
            return 10
        case .talkWalk:
            return 12
        default:
            return 8
        }
    }

    var loops: Int? {
        switch self {
        case .idleStretch, .errorFall, .eatToken, .evolveGlow:
            return 1
        case .idleBreathe, .thinkSweat, .talkWalk, .awaitJump:
            return nil
        }
    }

    static func from(state: CodexSessionState) -> PetAnimation {
        switch state {
        case .idle:
            return .idleBreathe
        case .thinking:
            return .thinkSweat
        case .working:
            return .thinkSweat
        case .streaming:
            return .talkWalk
        case .awaitingInput:
            return .awaitJump
        case .error:
            return .errorFall
        }
    }
}
