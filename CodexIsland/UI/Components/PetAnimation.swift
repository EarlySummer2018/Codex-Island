import Foundation

enum PetAnimation: String, Equatable {
    case idleBreathe = "idle_breathe"
    case idleStretch = "idle_stretch"
    case talkWalk = "talk_walk"
    case awaitJump = "await_jump"
    case errorFall = "error_fall"
    case eatToken = "eat_token"
    case happyBounce = "happy_bounce"
    case bubbleThink = "bubble_think"
    case outputBurst = "output_burst"
    case startledHop = "startled_hop"
    case dragHover = "drag_hover"
    case landBounce = "land_bounce"

    var frameCount: Int {
        switch self {
        case .idleBreathe:
            return 8
        case .idleStretch:
            return 12
        case .talkWalk:
            return 8
        case .awaitJump:
            return 10
        case .errorFall:
            return 10
        case .eatToken:
            return 8
        case .happyBounce:
            return 10
        case .bubbleThink:
            return 8
        case .outputBurst:
            return 8
        case .startledHop:
            return 8
        case .dragHover:
            return 8
        case .landBounce:
            return 8
        }
    }

    var fps: Int {
        switch self {
        case .talkWalk, .outputBurst:
            return 6
        case .awaitJump,
             .happyBounce,
             .startledHop,
             .landBounce:
            return 7
        case .dragHover:
            return 6
        case .idleBreathe:
            return 5
        default:
            return 6
        }
    }

    var loops: Int? {
        switch self {
        case .idleStretch,
             .errorFall,
             .eatToken,
             .happyBounce,
             .startledHop,
             .landBounce:
            return 1
        case .idleBreathe,
             .talkWalk,
             .awaitJump,
             .bubbleThink,
             .outputBurst,
             .dragHover:
            return nil
        }
    }

    static func from(state: CodexSessionState, level: Int = 0) -> PetAnimation {
        switch state {
        case .idle:
            return .idleBreathe
        case .thinking:
            return .bubbleThink
        case .working:
            return .bubbleThink
        case .streaming:
            return .outputBurst
        case .awaitingInput:
            return .awaitJump
        case .error:
            return .errorFall
        }
    }

    static func feedAnimation(for level: Int) -> PetAnimation {
        .eatToken
    }

    static func idleBreakAnimation(for level: Int) -> PetAnimation {
        return .idleStretch
    }

    var isIdleLoop: Bool {
        switch self {
        case .idleBreathe:
            return true
        default:
            return false
        }
    }
}

enum FurinaPetAtlasSpec {
    static let assetName = "FurinaPetSpritesheet"
    static let columns = 8
    static let rows = 9
    static let cellWidth = 192
    static let cellHeight = 208
    static let atlasWidth = columns * cellWidth
    static let atlasHeight = rows * cellHeight

    static func normalizedFrameIndex(_ frame: Int, for state: FurinaPetAtlasState) -> Int {
        let visibleColumns = max(visibleColumnCount(for: state), 1)
        let remainder = frame % visibleColumns
        return remainder >= 0 ? remainder : remainder + visibleColumns
    }

    static func visibleColumnCount(for state: FurinaPetAtlasState) -> Int {
        switch state {
        case .idle, .waiting, .running, .review:
            return 6
        case .runningRight, .runningLeft, .failed:
            return 8
        case .waving:
            return 4
        case .jumping:
            return 5
        }
    }
}

enum FurinaPetAtlasState: Int, CaseIterable, Equatable {
    case idle = 0
    case runningRight = 1
    case runningLeft = 2
    case waving = 3
    case jumping = 4
    case failed = 5
    case waiting = 6
    case running = 7
    case review = 8

    var row: Int {
        rawValue
    }
}

extension PetAnimation {
    var furinaAtlasState: FurinaPetAtlasState {
        switch self {
        case .idleBreathe:
            return .idle
        case .talkWalk, .outputBurst:
            return .running
        case .idleStretch, .happyBounce:
            return .waving
        case .awaitJump:
            return .waiting
        case .errorFall:
            return .failed
        case .eatToken, .bubbleThink:
            return .review
        case .startledHop, .dragHover, .landBounce:
            return .jumping
        }
    }

    var usesDirectionalFurinaMovementRows: Bool {
        switch self {
        case .talkWalk, .outputBurst:
            return true
        default:
            return false
        }
    }

    func furinaAtlasState(facingLeft: Bool?) -> FurinaPetAtlasState {
        guard usesDirectionalFurinaMovementRows else {
            return furinaAtlasState
        }

        return (facingLeft ?? false) ? .runningLeft : .runningRight
    }

    func furinaFrameCount(facingLeft: Bool?) -> Int {
        FurinaPetAtlasSpec.visibleColumnCount(for: furinaAtlasState(facingLeft: facingLeft))
    }
}
