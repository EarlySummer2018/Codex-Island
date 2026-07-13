import CoreGraphics
import Foundation

enum DesktopPetPhase: String, Equatable {
    case disabled
    case launching
    case roaming
    case dodging
    case dragging
    case dropped
    case waitingForCapsuleStill
    case returning
}

enum DesktopPetAction: String, Equatable {
    case idle
    case strolling
    case pausing
    case lookingAround
    case hopping
    case dodging
    case dragging
    case landing
    case returning
}

enum DesktopPetMetrics {
    static let windowSize = CGSize(width: 160, height: 180)
    static let petSize: CGFloat = 104
    static let capsulePetSize: CGFloat = 28
    static let desktopPresentationScale: CGFloat = 1
    static let capsulePresentationScale: CGFloat = capsulePetSize / petSize
    static let maxRoamDistance: CGFloat = 190
    static let singleClickDodgeDistance: CGFloat = 190
    static let idleSpeed: CGFloat = 70
    static let commandSpeed: CGFloat = 60
    static let replySpeed: CGFloat = 115
    static let reviewSpeed: CGFloat = 0
    static let launchSpeed: CGFloat = 120
    static let returnSpeed: CGFloat = 120
    static let capsuleAnchorStableTolerance: CGFloat = 2
    static let capsuleAnchorStableDelay: TimeInterval = 0.25
    static let capsuleAnchorPollDelay: TimeInterval = 0.12
}

enum DesktopPetBehaviorEngine {
    static func shouldPauseRoaming(
        for state: CodexSessionState,
        activity: CodexActivityKind = .none
    ) -> Bool {
        switch state {
        case .running:
            return activity == .reasoning
        case .waitingForInput, .readyForReview, .error:
            return true
        case .notLoaded, .idle:
            return false
        }
    }

    static func roamSpeed(
        for state: CodexSessionState,
        activity: CodexActivityKind = .none
    ) -> CGFloat {
        switch state {
        case .notLoaded, .idle:
            return DesktopPetMetrics.idleSpeed
        case .running:
            switch activity {
            case .reasoning:
                return 0
            case .commandExecution:
                return DesktopPetMetrics.commandSpeed
            case .fileChange, .agentMessage:
                return DesktopPetMetrics.replySpeed
            case .webSearch:
                return DesktopPetMetrics.idleSpeed
            case .none:
                return DesktopPetMetrics.commandSpeed
            }
        case .waitingForInput, .readyForReview, .error:
            return DesktopPetMetrics.reviewSpeed
        }
    }

    static func movingAnimation(
        for state: CodexSessionState,
        activity: CodexActivityKind = .none,
        level: Int = 0
    ) -> PetAnimation {
        switch state {
        case .running:
            switch activity {
            case .fileChange, .agentMessage:
                return .outputBurst
            case .none, .reasoning, .commandExecution, .webSearch:
                return .talkWalk
            }
        case .notLoaded, .idle, .waitingForInput, .readyForReview, .error:
            return .talkWalk
        }
    }
    static func clampedOrigin(
        _ origin: CGPoint,
        windowSize: CGSize,
        in frames: [CGRect]
    ) -> CGPoint {
        let validFrames = normalized(frames)
        guard !validFrames.isEmpty else {
            return origin
        }

        let center = CGPoint(
            x: origin.x + windowSize.width / 2,
            y: origin.y + windowSize.height / 2
        )
        let targetFrame = frame(containing: center, in: validFrames)
            ?? nearestFrame(to: center, in: validFrames)

        return clampedOrigin(origin, windowSize: windowSize, in: targetFrame)
    }

    static func launchTarget(
        from anchor: CGPoint,
        windowSize: CGSize,
        in frames: [CGRect]
    ) -> CGPoint {
        let proposed = CGPoint(
            x: anchor.x - windowSize.width / 2 + CGFloat.random(in: -48...48),
            y: anchor.y - windowSize.height - CGFloat.random(in: 96...150)
        )
        return clampedOrigin(proposed, windowSize: windowSize, in: frames)
    }

    static func returnOrigin(to anchor: CGPoint, windowSize: CGSize) -> CGPoint {
        origin(centeredOn: anchor, windowSize: windowSize)
    }

    static func origin(centeredOn anchor: CGPoint, windowSize: CGSize) -> CGPoint {
        CGPoint(
            x: anchor.x - windowSize.width / 2,
            y: anchor.y - windowSize.height / 2
        )
    }

    static func anchorsAreStable(
        _ lhs: CGPoint,
        _ rhs: CGPoint,
        tolerance: CGFloat = DesktopPetMetrics.capsuleAnchorStableTolerance
    ) -> Bool {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy <= tolerance * tolerance
    }

    static func roamingTarget(
        from origin: CGPoint,
        windowSize: CGSize,
        in frames: [CGRect],
        maxDistance: CGFloat = DesktopPetMetrics.maxRoamDistance
    ) -> CGPoint {
        let validFrames = normalized(frames)
        guard !validFrames.isEmpty else {
            return origin
        }

        let currentCenter = CGPoint(
            x: origin.x + windowSize.width / 2,
            y: origin.y + windowSize.height / 2
        )
        let targetFrame = frame(containing: currentCenter, in: validFrames)
            ?? nearestFrame(to: currentCenter, in: validFrames)
        let distance = CGFloat.random(in: 56...max(maxDistance, 56))
        let angle = CGFloat.random(in: 0..<(CGFloat.pi * 2))
        let proposedCenter = CGPoint(
            x: currentCenter.x + cos(angle) * distance,
            y: currentCenter.y + sin(angle) * distance
        )

        return clampedOrigin(
            CGPoint(
                x: proposedCenter.x - windowSize.width / 2,
                y: proposedCenter.y - windowSize.height / 2
            ),
            windowSize: windowSize,
            in: targetFrame
        )
    }

    static func attentionTarget(
        near anchor: CGPoint,
        windowSize: CGSize,
        in frames: [CGRect]
    ) -> CGPoint {
        let proposed = CGPoint(
            x: anchor.x - windowSize.width / 2,
            y: anchor.y - windowSize.height - 104
        )
        return clampedOrigin(proposed, windowSize: windowSize, in: frames)
    }

    static func dodgeTarget(
        from origin: CGPoint,
        clickLocation: CGPoint,
        windowSize: CGSize,
        in frames: [CGRect],
        clickCount: Int
    ) -> CGPoint {
        let validFrames = normalized(frames)
        guard !validFrames.isEmpty else {
            return origin
        }

        let currentCenter = CGPoint(
            x: origin.x + windowSize.width / 2,
            y: origin.y + windowSize.height / 2
        )
        let targetFrame = frame(containing: currentCenter, in: validFrames)
            ?? frame(containing: clickLocation, in: validFrames)
            ?? nearestFrame(to: currentCenter, in: validFrames)

        let isMultiClick = clickCount >= 2
        if isMultiClick {
            let targetCenter = CGPoint(
                x: currentCenter.x < targetFrame.midX
                    ? targetFrame.maxX - windowSize.width / 2 - 40
                    : targetFrame.minX + windowSize.width / 2 + 40,
                y: min(
                    max(clickLocation.y, targetFrame.minY + windowSize.height / 2 + 40),
                    targetFrame.maxY - windowSize.height / 2 - 40
                )
            )
            return clampedOrigin(
                CGPoint(
                    x: targetCenter.x - windowSize.width / 2,
                    y: targetCenter.y - windowSize.height / 2
                ),
                windowSize: windowSize,
                in: targetFrame
            )
        }

        let away = CGVector(
            dx: currentCenter.x - clickLocation.x,
            dy: currentCenter.y - clickLocation.y
        )
        let length = max(sqrt(away.dx * away.dx + away.dy * away.dy), 1)
        let unit: CGVector
        if length < 16 {
            unit = CGVector(
                dx: currentCenter.x < targetFrame.midX ? -1 : 1,
                dy: 0
            )
        } else {
            unit = CGVector(dx: away.dx / length, dy: away.dy / length)
        }

        let dodgeDistance = DesktopPetMetrics.singleClickDodgeDistance
        let targetCenter = CGPoint(
            x: currentCenter.x + unit.dx * dodgeDistance,
            y: currentCenter.y + unit.dy * dodgeDistance * 0.72
        )
        return clampedOrigin(
            CGPoint(
                x: targetCenter.x - windowSize.width / 2,
                y: targetCenter.y - windowSize.height / 2
            ),
            windowSize: windowSize,
            in: targetFrame
        )
    }

    static func normalized(_ frames: [CGRect]) -> [CGRect] {
        frames.filter { frame in
            !frame.isNull && !frame.isEmpty && frame.width > 1 && frame.height > 1
        }
    }

    private static func randomOrigin(
        windowSize: CGSize,
        in frame: CGRect
    ) -> CGPoint {
        let minX = frame.minX
        let maxX = max(minX, frame.maxX - windowSize.width)
        let minY = frame.minY
        let maxY = max(minY, frame.maxY - windowSize.height)

        return CGPoint(
            x: CGFloat.random(in: minX...maxX),
            y: CGFloat.random(in: minY...maxY)
        )
    }

    private static func clampedOrigin(
        _ origin: CGPoint,
        windowSize: CGSize,
        in frame: CGRect
    ) -> CGPoint {
        let minX = frame.minX
        let maxX = max(minX, frame.maxX - windowSize.width)
        let minY = frame.minY
        let maxY = max(minY, frame.maxY - windowSize.height)

        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    private static func frame(
        containing point: CGPoint,
        in frames: [CGRect]
    ) -> CGRect? {
        frames.first { frame in
            frame.contains(point)
        }
    }

    private static func nearestFrame(
        to point: CGPoint,
        in frames: [CGRect]
    ) -> CGRect {
        frames.min { lhs, rhs in
            squaredDistance(from: point, to: lhs) < squaredDistance(from: point, to: rhs)
        } ?? frames[0]
    }

    private static func squaredDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx: CGFloat
        if point.x < frame.minX {
            dx = frame.minX - point.x
        } else if point.x > frame.maxX {
            dx = point.x - frame.maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < frame.minY {
            dy = frame.minY - point.y
        } else if point.y > frame.maxY {
            dy = point.y - frame.maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }
}
