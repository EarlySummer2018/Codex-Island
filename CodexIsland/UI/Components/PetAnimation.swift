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
        }
    }

    var fps: Int {
        switch self {
        case .awaitJump, .happyBounce, .shieldWait, .tokenOrbit, .celebrateDance:
            return 10
        case .talkWalk, .outputBurst, .maxVictory:
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
             .maxVictory:
            return 1
        case .idleBreathe,
             .thinkSweat,
             .talkWalk,
             .awaitJump,
             .bubbleThink,
             .outputBurst,
             .hoverIdle,
             .shieldWait,
             .spiritIdle:
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
