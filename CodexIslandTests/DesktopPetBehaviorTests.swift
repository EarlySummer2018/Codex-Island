import AppKit
import CoreGraphics
import ImageIO
import XCTest
@testable import CodexIsland

final class DesktopPetBehaviorTests: XCTestCase {
    private let windowSize = DesktopPetMetrics.windowSize

    func testClampedOriginStaysInsideVisibleFrame() {
        let frame = CGRect(x: 100, y: 80, width: 500, height: 360)
        let origin = DesktopPetBehaviorEngine.clampedOrigin(
            CGPoint(x: -200, y: 900),
            windowSize: windowSize,
            in: [frame]
        )

        XCTAssertGreaterThanOrEqual(origin.x, frame.minX)
        XCTAssertGreaterThanOrEqual(origin.y, frame.minY)
        XCTAssertLessThanOrEqual(origin.x + windowSize.width, frame.maxX)
        XCTAssertLessThanOrEqual(origin.y + windowSize.height, frame.maxY)
    }

    func testSingleClickDodgeMovesAwayFromClick() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 500)
        let origin = CGPoint(x: 360, y: 220)
        let click = CGPoint(x: 390, y: 250)
        let target = DesktopPetBehaviorEngine.dodgeTarget(
            from: origin,
            clickLocation: click,
            windowSize: windowSize,
            in: [frame],
            clickCount: 1
        )

        let startDistance = distance(center(of: origin), click)
        let targetDistance = distance(center(of: target), click)

        XCTAssertGreaterThan(targetDistance, startDistance)
        XCTAssertTrue(frame.contains(center(of: target)))
        XCTAssertLessThanOrEqual(distance(center(of: origin), center(of: target)), 255)
    }

    func testMultiClickDodgeMovesToOppositeSideOfCurrentFrame() {
        let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
        let origin = CGPoint(x: 120, y: 260)
        let target = DesktopPetBehaviorEngine.dodgeTarget(
            from: origin,
            clickLocation: center(of: origin),
            windowSize: windowSize,
            in: [frame],
            clickCount: 3
        )

        XCTAssertGreaterThan(center(of: target).x, frame.midX)
        XCTAssertTrue(frame.contains(center(of: target)))
    }

    func testRoamingTargetUsesOneOfMultipleScreenFrames() {
        let left = CGRect(x: -700, y: 0, width: 640, height: 420)
        let right = CGRect(x: 0, y: 0, width: 800, height: 500)
        let target = DesktopPetBehaviorEngine.roamingTarget(
            from: .zero,
            windowSize: windowSize,
            in: [left, right]
        )
        let targetCenter = center(of: target)

        XCTAssertTrue(left.contains(targetCenter) || right.contains(targetCenter))
    }

    func testRoamingTargetStaysNearCurrentOrigin() {
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let origin = CGPoint(x: 540, y: 390)
        let target = DesktopPetBehaviorEngine.roamingTarget(
            from: origin,
            windowSize: windowSize,
            in: [frame],
            maxDistance: DesktopPetMetrics.maxRoamDistance
        )

        XCTAssertLessThanOrEqual(
            distance(center(of: origin), center(of: target)),
            DesktopPetMetrics.maxRoamDistance + 1
        )
    }

    func testLevelBadgeTextAndPixelsAreValid() {
        XCTAssertEqual(PixelLevelBadgeText.text(for: 0), "LV.0")
        XCTAssertEqual(PixelLevelBadgeText.text(for: 9), "LV.9")
        XCTAssertEqual(PixelLevelBadgeText.text(for: 100), "LV.100")
        XCTAssertEqual(PixelLevelBadgeText.text(for: 120), "LV.100")

        XCTAssertFalse(PixelLevelBadgeRenderer.pixelRuns(for: "LV.0").isEmpty)
        XCTAssertFalse(PixelLevelBadgeRenderer.pixelRuns(for: "LV.100").isEmpty)
        XCTAssertGreaterThan(
            PixelLevelBadgeRenderer.canvasSize(for: 100).width,
            PixelLevelBadgeRenderer.canvasSize(for: 9).width
        )
    }

    func testLevelBadgeCanvasStaysCompactAboveDesktopPet() {
        let largestBadge = PixelLevelBadgeRenderer.canvasSize(for: 100)

        XCTAssertLessThanOrEqual(largestBadge.width, 52)
        XCTAssertLessThanOrEqual(largestBadge.height, 16)
    }

    func testCapsulePresentationScaleMatchesCapsulePetSize() {
        XCTAssertEqual(
            DesktopPetMetrics.capsulePresentationScale,
            DesktopPetMetrics.capsulePetSize / DesktopPetMetrics.petSize,
            accuracy: 0.001
        )
        XCTAssertGreaterThan(DesktopPetMetrics.capsulePresentationScale, 0.35)
        XCTAssertLessThan(DesktopPetMetrics.capsulePresentationScale, 0.40)
    }

    func testReturnOriginCentersWindowOnCapsuleAnchor() {
        let anchor = CGPoint(x: 420, y: 760)
        let origin = DesktopPetBehaviorEngine.returnOrigin(
            to: anchor,
            windowSize: windowSize
        )

        XCTAssertEqual(center(of: origin).x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(center(of: origin).y, anchor.y, accuracy: 0.001)
    }

    func testCapsuleAnchorStabilityUsesTolerance() {
        let anchor = CGPoint(x: 100, y: 200)

        XCTAssertTrue(
            DesktopPetBehaviorEngine.anchorsAreStable(
                anchor,
                CGPoint(x: 101.2, y: 200.8)
            )
        )
        XCTAssertFalse(
            DesktopPetBehaviorEngine.anchorsAreStable(
                anchor,
                CGPoint(x: 103.1, y: 200)
            )
        )
    }

    func testCapsuleSavedPositionAllowsOffscreenRatios() {
        let usableFrame = CGRect(x: 0, y: 100, width: 1000, height: 700)
        let offscreenFrame = CGRect(x: -140, y: 840, width: 360, height: 34)

        let position = IslandPositionGeometry.position(
            for: offscreenFrame,
            usableFrame: usableFrame
        )
        let restoredOrigin = IslandPositionGeometry.origin(
            for: offscreenFrame.size,
            usableFrame: usableFrame,
            position: position
        )

        XCTAssertLessThan(position.xRatio, 0)
        XCTAssertGreaterThan(position.yRatio, 1)
        XCTAssertEqual(restoredOrigin.x, offscreenFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restoredOrigin.y, offscreenFrame.minY, accuracy: 0.001)
    }

    func testMovingAnimationsAlwaysUseStrideFrames() {
        XCTAssertEqual(DesktopPetBehaviorEngine.movingAnimation(for: .idle), .talkWalk)
        XCTAssertEqual(DesktopPetBehaviorEngine.movingAnimation(for: .thinking), .talkWalk)
        XCTAssertEqual(DesktopPetBehaviorEngine.movingAnimation(for: .working), .talkWalk)
        XCTAssertEqual(DesktopPetBehaviorEngine.movingAnimation(for: .streaming), .outputBurst)
    }

    func testFurinaAtlasGeometryMatchesCodexPetsContract() {
        XCTAssertEqual(FurinaPetAtlasSpec.columns, 8)
        XCTAssertEqual(FurinaPetAtlasSpec.rows, 9)
        XCTAssertEqual(FurinaPetAtlasSpec.cellWidth, 192)
        XCTAssertEqual(FurinaPetAtlasSpec.cellHeight, 208)
        XCTAssertEqual(FurinaPetAtlasSpec.atlasWidth, 1536)
        XCTAssertEqual(FurinaPetAtlasSpec.atlasHeight, 1872)
    }

    func testFurinaSpritesheetDataAssetIsBundled() {
        guard let dataAsset = NSDataAsset(name: FurinaPetAtlasSpec.assetName) else {
            XCTFail("Expected bundled Furina spritesheet data asset")
            return
        }

        guard let imageSource = CGImageSourceCreateWithData(dataAsset.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            XCTFail("Expected Furina spritesheet WebP to decode")
            return
        }

        XCTAssertEqual(image.width, FurinaPetAtlasSpec.atlasWidth)
        XCTAssertEqual(image.height, FurinaPetAtlasSpec.atlasHeight)
    }

    func testPetAnimationsMapToFurinaAtlasRows() {
        XCTAssertEqual(PetAnimation.idleBreathe.furinaAtlasState, .idle)
        XCTAssertEqual(PetAnimation.thinkSweat.furinaAtlasState, .review)
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState, .running)
        XCTAssertEqual(PetAnimation.outputBurst.furinaAtlasState, .running)
        XCTAssertEqual(PetAnimation.awaitJump.furinaAtlasState, .waiting)
        XCTAssertEqual(PetAnimation.errorFall.furinaAtlasState, .failed)
        XCTAssertEqual(PetAnimation.evolveGlow.furinaAtlasState, .waving)
        XCTAssertEqual(PetAnimation.dragHover.furinaAtlasState, .jumping)
    }

    func testDirectionalMovementUsesFurinaLeftAndRightRows() {
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState(facingLeft: false), .runningRight)
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState(facingLeft: true), .runningLeft)
        XCTAssertEqual(PetAnimation.outputBurst.furinaAtlasState(facingLeft: false), .runningRight)
        XCTAssertEqual(PetAnimation.idleBreathe.furinaAtlasState(facingLeft: true), .idle)
    }

    func testFurinaFrameIndexWrapsToAtlasColumns() {
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(0), 0)
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(7), 7)
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(8), 0)
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(15), 7)
    }

    func testRoamingSpeedsFollowStatePriority() {
        XCTAssertGreaterThan(
            DesktopPetBehaviorEngine.roamSpeed(for: .streaming),
            DesktopPetBehaviorEngine.roamSpeed(for: .idle)
        )
        XCTAssertGreaterThan(
            DesktopPetBehaviorEngine.roamSpeed(for: .idle),
            DesktopPetBehaviorEngine.roamSpeed(for: .thinking)
        )
        XCTAssertGreaterThan(
            DesktopPetBehaviorEngine.roamSpeed(for: .working),
            DesktopPetBehaviorEngine.roamSpeed(for: .thinking)
        )
    }

    func testAwaitingAndErrorPauseFreeRoaming() {
        XCTAssertFalse(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .idle))
        XCTAssertFalse(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .streaming))
        XCTAssertTrue(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .awaitingInput))
        XCTAssertTrue(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .error))
    }

    func testStatusEffectFollowsSessionState() {
        XCTAssertEqual(DesktopPetBehaviorEngine.statusEffect(for: .idle), .none)
        XCTAssertEqual(DesktopPetBehaviorEngine.statusEffect(for: .thinking), .thinking)
        XCTAssertEqual(DesktopPetBehaviorEngine.statusEffect(for: .working), .working)
        XCTAssertEqual(DesktopPetBehaviorEngine.statusEffect(for: .streaming), .streaming)
        XCTAssertEqual(DesktopPetBehaviorEngine.statusEffect(for: .awaitingInput), .awaitingInput)
        XCTAssertEqual(DesktopPetBehaviorEngine.statusEffect(for: .error), .error)
    }

    func testIpcDecoderRecognizesDailyTokenUsage() {
        let line = """
        {"type":"daily_token_usage","local_date":"2026-07-01","total_input":120,"total_cached_input":30,"total_output":45,"total_reasoning":5,"total_tokens":165,"session_count":3,"updated_at":"2026-07-01T08:00:00Z"}
        """

        switch IpcEventDecoder().decode(line: line) {
        case .dailyToken(let snapshot):
            XCTAssertEqual(snapshot.localDate, "2026-07-01")
            XCTAssertEqual(snapshot.totalTokens, 165)
            XCTAssertEqual(snapshot.sessionCount, 3)
        default:
            XCTFail("Expected daily token snapshot")
        }
    }

    private func center(of origin: CGPoint) -> CGPoint {
        CGPoint(
            x: origin.x + windowSize.width / 2,
            y: origin.y + windowSize.height / 2
        )
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }
}
