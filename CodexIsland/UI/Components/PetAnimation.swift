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
    case happyBounce = "happy_bounce"
    case nap
    case bubbleThink = "bubble_think"
    case outputBurst = "output_burst"
    case hoverIdle = "hover_idle"
    case shieldWait = "shield_wait"
    case tokenOrbit = "token_orbit"
    case celebrateDance = "celebrate_dance"
    case spiritIdle = "spirit_idle"
    case maxVictory = "max_victory"
    case startledHop = "startled_hop"
    case dragHover = "drag_hover"
    case landBounce = "land_bounce"

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
        case .happyBounce:
            return 10
        case .nap:
            return 12
        case .bubbleThink:
            return 8
        case .outputBurst:
            return 8
        case .hoverIdle:
            return 8
        case .shieldWait:
            return 10
        case .tokenOrbit:
            return 12
        case .celebrateDance:
            return 12
        case .spiritIdle:
            return 8
        case .maxVictory:
            return 16
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
        case .awaitJump, .happyBounce, .shieldWait, .tokenOrbit, .celebrateDance, .startledHop, .landBounce:
            return 10
        case .talkWalk, .outputBurst, .maxVictory, .dragHover:
            return 12
        case .nap:
            return 6
        default:
            return 8
        }
    }

    var loops: Int? {
        switch self {
        case .idleStretch,
             .errorFall,
             .eatToken,
             .evolveGlow,
             .happyBounce,
             .nap,
             .tokenOrbit,
             .celebrateDance,
             .maxVictory,
             .startledHop,
             .landBounce:
            return 1
        case .idleBreathe,
             .thinkSweat,
             .talkWalk,
             .awaitJump,
             .bubbleThink,
             .outputBurst,
             .hoverIdle,
             .shieldWait,
             .spiritIdle,
             .dragHover:
            return nil
        }
    }

    static func from(state: CodexSessionState, level: Int = 0) -> PetAnimation {
        switch state {
        case .idle:
            if level >= 90 {
                return .spiritIdle
            }

            if level >= 50 {
                return .hoverIdle
            }

            return .idleBreathe
        case .thinking:
            return level >= 30 ? .bubbleThink : .thinkSweat
        case .working:
            return level >= 30 ? .bubbleThink : .thinkSweat
        case .streaming:
            return level >= 40 ? .outputBurst : .talkWalk
        case .awaitingInput:
            return level >= 60 ? .shieldWait : .awaitJump
        case .error:
            return .errorFall
        }
    }

    static func feedAnimation(for level: Int) -> PetAnimation {
        level >= 70 ? .tokenOrbit : .eatToken
    }

    static func levelUpAnimation(for level: Int) -> PetAnimation {
        if level >= PetLevelCurve.maxLevel {
            return .maxVictory
        }

        if level >= 80 {
            return .celebrateDance
        }

        return .evolveGlow
    }

    static func idleBreakAnimation(for level: Int) -> PetAnimation {
        if level >= 20 {
            return .nap
        }

        if level >= 10 {
            return .happyBounce
        }

        return .idleStretch
    }

    var isIdleLoop: Bool {
        switch self {
        case .idleBreathe, .hoverIdle, .spiritIdle:
            return true
        default:
            return false
        }
    }
}

enum PetStatusEffect: String, Equatable {
    case none
    case thinking
    case working
    case streaming
    case awaitingInput
    case error
    case dragging
    case levelUp

    static func from(state: CodexSessionState) -> PetStatusEffect {
        switch state {
        case .idle:
            return .none
        case .thinking:
            return .thinking
        case .working:
            return .working
        case .streaming:
            return .streaming
        case .awaitingInput:
            return .awaitingInput
        case .error:
            return .error
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

    static func normalizedFrameIndex(_ frame: Int) -> Int {
        let remainder = frame % columns
        return remainder >= 0 ? remainder : remainder + columns
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
        case .idleBreathe, .hoverIdle, .spiritIdle, .nap:
            return .idle
        case .talkWalk, .outputBurst:
            return .running
        case .idleStretch, .happyBounce, .evolveGlow, .celebrateDance, .maxVictory:
            return .waving
        case .awaitJump, .shieldWait:
            return .waiting
        case .errorFall:
            return .failed
        case .eatToken, .thinkSweat, .bubbleThink, .tokenOrbit:
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
        guard usesDirectionalFurinaMovementRows,
              let facingLeft else {
            return furinaAtlasState
        }

        return facingLeft ? .runningLeft : .runningRight
    }

    var inferredStatusEffect: PetStatusEffect {
        switch self {
        case .thinkSweat, .bubbleThink:
            return .thinking
        case .outputBurst:
            return .streaming
        case .awaitJump, .shieldWait:
            return .awaitingInput
        case .errorFall:
            return .error
        case .dragHover:
            return .dragging
        case .evolveGlow, .celebrateDance, .maxVictory:
            return .levelUp
        case .idleBreathe,
             .idleStretch,
             .talkWalk,
             .eatToken,
             .happyBounce,
             .nap,
             .hoverIdle,
             .tokenOrbit,
             .spiritIdle,
             .startledHop,
             .landBounce:
            return .none
        }
    }
}
