import CoreGraphics
import Foundation

enum DesktopPetPhase: String, Equatable {
    case disabled
    case launching
    case roaming
    case dodging
    case dragging
    case resizing
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
    static let baseWindowSize = CGSize(width: 160, height: 180)
    static let windowSize = baseWindowSize
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

enum DesktopPetScale {
    static let minimum: CGFloat = 0.5
    static let maximum: CGFloat = 2

    static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale.isFinite ? scale : 1, minimum), maximum)
    }

    static func windowSize(for scale: CGFloat) -> CGSize {
        let resolvedScale = clamped(scale)
        return CGSize(
            width: DesktopPetMetrics.baseWindowSize.width * resolvedScale,
            height: DesktopPetMetrics.baseWindowSize.height * resolvedScale
        )
    }

    static func capsulePresentationScale(for scale: CGFloat) -> CGFloat {
        DesktopPetMetrics.capsulePetSize
            / (DesktopPetMetrics.petSize * clamped(scale))
    }
}

enum DesktopPetRoamingPolicy {
    static let idleRestDelayRange: ClosedRange<TimeInterval> = 20...40

    static func idleRestDelay(randomUnit: Double = Double.random(in: 0...1)) -> TimeInterval {
        let unit = min(max(randomUnit.isFinite ? randomUnit : 0.5, 0), 1)
        return idleRestDelayRange.lowerBound
            + (idleRestDelayRange.upperBound - idleRestDelayRange.lowerBound) * unit
    }
}

enum DesktopPetScrollScaling {
    static let wheelStep: CGFloat = 0.05
    static let preciseSensitivity: CGFloat = 0.01
    static let finishDelay: TimeInterval = 0.25

    static func acceptsEvent(
        deltaY: CGFloat,
        hasMomentum: Bool,
        phaseEnded: Bool
    ) -> Bool {
        !hasMomentum && (abs(deltaY) > 0.001 || phaseEnded)
    }

    static func scale(
        from currentScale: CGFloat,
        deltaY: CGFloat,
        isPrecise: Bool
    ) -> CGFloat {
        guard deltaY.isFinite, abs(deltaY) > 0.001 else {
            return DesktopPetScale.clamped(currentScale)
        }

        let multiplier: CGFloat
        if isPrecise {
            let limitedDelta = min(max(deltaY, -12), 12)
            multiplier = exp(limitedDelta * preciseSensitivity)
        } else {
            multiplier = 1 + (deltaY > 0 ? wheelStep : -wheelStep)
        }
        return DesktopPetScale.clamped(currentScale * multiplier)
    }
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

struct DesktopPetDisplayGeometry: Equatable {
    let identifier: String
    let visibleFrame: CGRect
}

struct DesktopPetSavedPosition: Codable, Equatable {
    let screenIdentifier: String
    let xRatio: Double
    let yRatio: Double
    let absoluteCenterX: Double
    let absoluteCenterY: Double
}

enum DesktopPetPositionGeometry {
    static func savedPosition(
        for windowFrame: CGRect,
        on display: DesktopPetDisplayGeometry
    ) -> DesktopPetSavedPosition {
        let visibleFrame = display.visibleFrame
        let xRatio = visibleFrame.width > 0
            ? (windowFrame.midX - visibleFrame.minX) / visibleFrame.width
            : 0.5
        let yRatio = visibleFrame.height > 0
            ? (windowFrame.midY - visibleFrame.minY) / visibleFrame.height
            : 0.5

        return DesktopPetSavedPosition(
            screenIdentifier: display.identifier,
            xRatio: Double(xRatio),
            yRatio: Double(yRatio),
            absoluteCenterX: Double(windowFrame.midX),
            absoluteCenterY: Double(windowFrame.midY)
        )
    }

    static func restoredOrigin(
        from savedPosition: DesktopPetSavedPosition,
        windowSize: CGSize,
        displays: [DesktopPetDisplayGeometry]
    ) -> CGPoint? {
        let validDisplays = displays.filter {
            !$0.visibleFrame.isNull
                && !$0.visibleFrame.isEmpty
                && $0.visibleFrame.width > 1
                && $0.visibleFrame.height > 1
        }
        guard !validDisplays.isEmpty else {
            return nil
        }

        let savedCenter = CGPoint(
            x: savedPosition.absoluteCenterX,
            y: savedPosition.absoluteCenterY
        )
        let display = validDisplays.first {
            $0.identifier == savedPosition.screenIdentifier
        } ?? validDisplays.min {
            squaredDistance(from: savedCenter, to: $0.visibleFrame)
                < squaredDistance(from: savedCenter, to: $1.visibleFrame)
        }!
        let center = CGPoint(
            x: display.visibleFrame.minX + display.visibleFrame.width * savedPosition.xRatio,
            y: display.visibleFrame.minY + display.visibleFrame.height * savedPosition.yRatio
        )
        let proposed = CGPoint(
            x: center.x - windowSize.width / 2,
            y: center.y - windowSize.height / 2
        )
        return DesktopPetBehaviorEngine.clampedOrigin(
            proposed,
            windowSize: windowSize,
            in: [display.visibleFrame]
        )
    }

    private static func squaredDistance(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return dx * dx + dy * dy
    }
}

final class DesktopPetPositionStore {
    private let defaults: UserDefaults
    private let positionsKey = "CodexIsland.DesktopPet.positions"
    private let lastScreenKey = "CodexIsland.DesktopPet.position.lastScreenID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(windowFrame: CGRect, on display: DesktopPetDisplayGeometry) {
        var positions = loadPositions()
        positions[display.identifier] = DesktopPetPositionGeometry.savedPosition(
            for: windowFrame,
            on: display
        )
        guard let data = try? JSONEncoder().encode(positions) else {
            return
        }

        defaults.set(data, forKey: positionsKey)
        defaults.set(display.identifier, forKey: lastScreenKey)
    }

    func restoredOrigin(
        windowSize: CGSize,
        displays: [DesktopPetDisplayGeometry]
    ) -> CGPoint? {
        let positions = loadPositions()
        let preferred = defaults.string(forKey: lastScreenKey)
            .flatMap { positions[$0] }
            ?? positions.values.first
        guard let preferred else {
            return nil
        }

        if displays.contains(where: { $0.identifier == preferred.screenIdentifier }) {
            return DesktopPetPositionGeometry.restoredOrigin(
                from: preferred,
                windowSize: windowSize,
                displays: displays
            )
        }

        let center = CGPoint(
            x: preferred.absoluteCenterX,
            y: preferred.absoluteCenterY
        )
        guard let fallbackDisplay = displays.min(by: {
            distanceSquared(from: center, to: $0.visibleFrame)
                < distanceSquared(from: center, to: $1.visibleFrame)
        }) else {
            return nil
        }
        let fallbackPosition = positions[fallbackDisplay.identifier] ?? preferred

        return DesktopPetPositionGeometry.restoredOrigin(
            from: fallbackPosition,
            windowSize: windowSize,
            displays: [fallbackDisplay]
        )
    }

    private func distanceSquared(from point: CGPoint, to frame: CGRect) -> CGFloat {
        let dx = max(max(frame.minX - point.x, 0), point.x - frame.maxX)
        let dy = max(max(frame.minY - point.y, 0), point.y - frame.maxY)
        return dx * dx + dy * dy
    }

    private func loadPositions() -> [String: DesktopPetSavedPosition] {
        guard let data = defaults.data(forKey: positionsKey),
              let positions = try? JSONDecoder().decode(
                  [String: DesktopPetSavedPosition].self,
                  from: data
              ) else {
            return [:]
        }

        return positions
    }
}

struct DesktopPetInteractionLayout: Equatable {
    let petBounds: CGRect
    let levelBadgeBounds: CGRect
    let contentBounds: CGRect
    let interactionBounds: CGRect
    let petFootAnchor: CGPoint
}

enum DesktopPetInteractionGeometry {
    static let resizeHandleSize = CGSize(width: 22, height: 22)
    static let resizeHandleSymbolName = "arrow.up.right.and.arrow.down.left"

    static func layout(
        userScale: CGFloat,
        presentationScale: CGFloat = 1,
        level: Int,
        normalizedOpaqueBounds: CGRect?
    ) -> DesktopPetInteractionLayout {
        let scale = DesktopPetScale.clamped(userScale)
        let windowSize = DesktopPetScale.windowSize(for: scale)
        let badgeSize = PixelLevelBadgeRenderer.canvasSize(for: level)
        let petFrame = petFrame(
            badgeSize: badgeSize,
            petSize: DesktopPetMetrics.petSize * scale,
            windowSize: windowSize
        )
        let opaqueBounds = normalizedOpaqueBounds.flatMap { normalized in
            mappedOpaqueBounds(normalized, in: petFrame)
        } ?? petFrame
        let badgeFrame = CGRect(
            x: (windowSize.width - badgeSize.width) / 2,
            y: petFrame.maxY + 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
        let presentationCenter = CGPoint(
            x: windowSize.width / 2,
            y: windowSize.height / 2
        )
        let resolvedPresentationScale = max(presentationScale, 0)
        let presentedPetBounds = scaled(
            opaqueBounds,
            around: presentationCenter,
            by: resolvedPresentationScale
        )
        let presentedBadgeBounds = scaled(
            badgeFrame,
            around: presentationCenter,
            by: resolvedPresentationScale
        )
        let contentBounds = presentedPetBounds.union(presentedBadgeBounds)
        let padding = min(max(8 * scale, 4), 16)
        let interactionBounds = contentBounds
            .insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(origin: .zero, size: windowSize))
        let petFoot = scaled(
            CGPoint(x: opaqueBounds.midX, y: opaqueBounds.minY),
            around: presentationCenter,
            by: resolvedPresentationScale
        )

        return DesktopPetInteractionLayout(
            petBounds: presentedPetBounds,
            levelBadgeBounds: presentedBadgeBounds,
            contentBounds: contentBounds,
            interactionBounds: interactionBounds,
            petFootAnchor: petFoot
        )
    }

    static func resizeHandleFrame(in localBounds: CGRect) -> CGRect {
        CGRect(
            x: localBounds.maxX - resizeHandleSize.width,
            y: localBounds.maxY - resizeHandleSize.height,
            width: resizeHandleSize.width,
            height: resizeHandleSize.height
        )
    }

    static func scale(
        startScale: CGFloat,
        startVector: CGVector,
        currentVector: CGVector
    ) -> CGFloat {
        let denominator = startVector.dx * startVector.dx + startVector.dy * startVector.dy
        guard denominator > 1 else {
            return DesktopPetScale.clamped(startScale)
        }
        let projection = (
            currentVector.dx * startVector.dx + currentVector.dy * startVector.dy
        ) / denominator
        return DesktopPetScale.clamped(startScale * projection)
    }

    private static func petFrame(
        badgeSize: CGSize,
        petSize: CGFloat,
        windowSize: CGSize
    ) -> CGRect {
        let contentHeight = badgeSize.height + 2 + petSize
        let contentMinY = (windowSize.height - contentHeight) / 2
        return CGRect(
            x: (windowSize.width - petSize) / 2,
            y: contentMinY,
            width: petSize,
            height: petSize
        )
    }

    private static func mappedOpaqueBounds(_ normalized: CGRect, in petFrame: CGRect) -> CGRect {
        let sourceSize = CGSize(
            width: PetAtlasSpec.cellWidth,
            height: PetAtlasSpec.cellHeight
        )
        let fitScale = min(
            petFrame.width / sourceSize.width,
            petFrame.height / sourceSize.height
        )
        let fittedSize = CGSize(
            width: sourceSize.width * fitScale,
            height: sourceSize.height * fitScale
        )
        let fittedOrigin = CGPoint(
            x: petFrame.midX - fittedSize.width / 2,
            y: petFrame.midY - fittedSize.height / 2
        )
        return CGRect(
            x: fittedOrigin.x + normalized.minX * fittedSize.width,
            y: fittedOrigin.y + normalized.minY * fittedSize.height,
            width: normalized.width * fittedSize.width,
            height: normalized.height * fittedSize.height
        )
    }

    private static func scaled(_ rect: CGRect, around anchor: CGPoint, by scale: CGFloat) -> CGRect {
        CGRect(
            x: anchor.x + (rect.minX - anchor.x) * scale,
            y: anchor.y + (rect.minY - anchor.y) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private static func scaled(_ point: CGPoint, around anchor: CGPoint, by scale: CGFloat) -> CGPoint {
        CGPoint(
            x: anchor.x + (point.x - anchor.x) * scale,
            y: anchor.y + (point.y - anchor.y) * scale
        )
    }
}
