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
        XCTAssertGreaterThan(DesktopPetMetrics.capsulePresentationScale, 0.26)
        XCTAssertLessThan(DesktopPetMetrics.capsulePresentationScale, 0.28)
    }

    func testCapsuleSizeShrinksWhenDesktopPetIsEnabled() {
        XCTAssertEqual(CapsuleDisplayStyle.large.pillSize(desktopPetEnabled: false).width, 360)
        XCTAssertEqual(CapsuleDisplayStyle.small.pillSize(desktopPetEnabled: false).width, 148)
        XCTAssertEqual(CapsuleDisplayStyle.large.pillSize(desktopPetEnabled: true).width, 324)
        XCTAssertEqual(CapsuleDisplayStyle.small.pillSize(desktopPetEnabled: true).width, 112)
    }

    func testDesktopPetUsesLargerBodyWithoutScalingLevelBadge() {
        XCTAssertEqual(DesktopPetMetrics.petSize, 104)
        XCTAssertEqual(DesktopPetMetrics.windowSize.width, 160)
        XCTAssertEqual(DesktopPetMetrics.windowSize.height, 180)

        let largestBadge = PixelLevelBadgeRenderer.canvasSize(for: 100)
        XCTAssertLessThanOrEqual(largestBadge.width, 52)
        XCTAssertLessThanOrEqual(largestBadge.height, 16)
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

        XCTAssertGreaterThan(position.yRatio, 1)
        XCTAssertEqual(restoredOrigin.x, offscreenFrame.minX, accuracy: 0.001)
        XCTAssertEqual(restoredOrigin.y, offscreenFrame.minY, accuracy: 0.001)
    }

    func testIslandInteractionHitAreasPrioritizeSettingsThenHeaderDrag() {
        let expandedBounds = CGRect(x: 0, y: 0, width: 440, height: 290)
        let settingsFrame = IslandInteractionHitTest.settingsButtonFrame(
            in: expandedBounds,
            isFlipped: true
        )

        XCTAssertEqual(
            IslandInteractionHitTest.region(
                for: CGPoint(x: settingsFrame.midX, y: settingsFrame.midY),
                in: expandedBounds,
                isFlipped: true
            ),
            .settingsButton
        )
        XCTAssertEqual(
            IslandInteractionHitTest.region(
                for: CGPoint(x: 34, y: 32),
                in: expandedBounds,
                isFlipped: true
            ),
            .drag
        )
        XCTAssertEqual(
            IslandInteractionHitTest.region(
                for: CGPoint(x: 220, y: 120),
                in: expandedBounds,
                isFlipped: true
            ),
            .content
        )
        XCTAssertEqual(
            IslandInteractionHitTest.region(
                for: CGPoint(x: 90, y: 18),
                in: CGRect(x: 0, y: 0, width: 220, height: 34),
                isFlipped: true
            ),
            .drag
        )
    }

    func testIslandPressGestureSeparatesClickFromDrag() {
        let start = CGPoint(x: 40, y: 40)

        XCTAssertTrue(IslandPressGesture.isClick(from: start, to: CGPoint(x: 42, y: 43)))
        XCTAssertFalse(IslandPressGesture.isClick(from: start, to: CGPoint(x: 45, y: 40)))
        XCTAssertTrue(IslandPressGesture.isDrag(from: start, to: CGPoint(x: 45, y: 40)))
    }

    func testCapsuleSavedPositionPreservesCenterAcrossSizeChanges() {
        let usableFrame = CGRect(x: 0, y: 100, width: 1000, height: 700)
        let expandedFrame = CGRect(x: 250, y: 380, width: 440, height: 290)
        let compactSize = CGSize(width: 360, height: 34)

        let position = IslandPositionGeometry.position(
            for: expandedFrame,
            usableFrame: usableFrame
        )
        let restoredOrigin = IslandPositionGeometry.origin(
            for: compactSize,
            usableFrame: usableFrame,
            position: position
        )

        XCTAssertEqual(
            restoredOrigin.x + compactSize.width / 2,
            expandedFrame.midX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredOrigin.y + compactSize.height / 2,
            expandedFrame.midY,
            accuracy: 0.001
        )
    }

    func testMovingAnimationsAlwaysUseStrideFrames() {
        XCTAssertEqual(DesktopPetBehaviorEngine.movingAnimation(for: .idle), .talkWalk)
        XCTAssertEqual(
            DesktopPetBehaviorEngine.movingAnimation(for: .running, activity: .commandExecution),
            .talkWalk
        )
        XCTAssertEqual(
            DesktopPetBehaviorEngine.movingAnimation(for: .running, activity: .webSearch),
            .talkWalk
        )
        XCTAssertEqual(
            DesktopPetBehaviorEngine.movingAnimation(for: .running, activity: .fileChange),
            .outputBurst
        )
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
        XCTAssertEqual(PetAnimation.bubbleThink.furinaAtlasState, .review)
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState, .running)
        XCTAssertEqual(PetAnimation.outputBurst.furinaAtlasState, .running)
        XCTAssertEqual(PetAnimation.awaitJump.furinaAtlasState, .waiting)
        XCTAssertEqual(PetAnimation.errorFall.furinaAtlasState, .failed)
        XCTAssertEqual(PetAnimation.dragHover.furinaAtlasState, .jumping)
    }

    func testPetAnimationsDoNotUseLevelSpecificBodyShapes() {
        XCTAssertEqual(PetAnimation.from(state: .idle, level: 0), .idleBreathe)
        XCTAssertEqual(PetAnimation.from(state: .idle, level: 100), .idleBreathe)
        XCTAssertEqual(
            PetAnimation.from(state: .running, activityKind: .reasoning, level: 0),
            .bubbleThink
        )
        XCTAssertEqual(
            PetAnimation.from(state: .running, activityKind: .reasoning, level: 100),
            .bubbleThink
        )
        XCTAssertEqual(PetAnimation.feedAnimation(for: 0), .eatToken)
        XCTAssertEqual(PetAnimation.feedAnimation(for: 100), .eatToken)
        XCTAssertEqual(PetAnimation.idleBreakAnimation(for: 0), .idleStretch)
        XCTAssertEqual(PetAnimation.idleBreakAnimation(for: 100), .idleStretch)
    }

    func testDirectionalMovementUsesFurinaLeftAndRightRows() {
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState(facingLeft: nil), .runningRight)
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState(facingLeft: false), .runningRight)
        XCTAssertEqual(PetAnimation.talkWalk.furinaAtlasState(facingLeft: true), .runningLeft)
        XCTAssertEqual(PetAnimation.outputBurst.furinaAtlasState(facingLeft: nil), .runningRight)
        XCTAssertEqual(PetAnimation.outputBurst.furinaAtlasState(facingLeft: false), .runningRight)
        XCTAssertEqual(PetAnimation.idleBreathe.furinaAtlasState(facingLeft: true), .idle)
    }

    func testFurinaFrameIndexWrapsToAtlasColumns() {
        XCTAssertEqual(FurinaPetAtlasSpec.visibleColumnCount(for: .idle), 6)
        XCTAssertEqual(FurinaPetAtlasSpec.visibleColumnCount(for: .waving), 4)
        XCTAssertEqual(FurinaPetAtlasSpec.visibleColumnCount(for: .jumping), 5)
        XCTAssertEqual(FurinaPetAtlasSpec.visibleColumnCount(for: .runningRight), 8)

        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(5, for: .idle), 5)
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(6, for: .idle), 0)
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(7, for: .waving), 3)
        XCTAssertEqual(FurinaPetAtlasSpec.normalizedFrameIndex(8, for: .runningRight), 0)
    }

    func testRoamingSpeedsFollowStatePriority() {
        XCTAssertGreaterThan(
            DesktopPetBehaviorEngine.roamSpeed(for: .running, activity: .agentMessage),
            DesktopPetBehaviorEngine.roamSpeed(for: .idle)
        )
        XCTAssertGreaterThan(
            DesktopPetBehaviorEngine.roamSpeed(for: .idle),
            DesktopPetBehaviorEngine.roamSpeed(for: .running, activity: .commandExecution)
        )
        XCTAssertGreaterThan(
            DesktopPetBehaviorEngine.roamSpeed(for: .running, activity: .commandExecution),
            DesktopPetBehaviorEngine.roamSpeed(for: .running, activity: .reasoning)
        )
        XCTAssertEqual(DesktopPetBehaviorEngine.roamSpeed(for: .running, activity: .reasoning), 0)
    }

    func testReasoningAwaitingReviewAndErrorPauseFreeRoaming() {
        XCTAssertFalse(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .idle))
        XCTAssertFalse(
            DesktopPetBehaviorEngine.shouldPauseRoaming(for: .running, activity: .commandExecution)
        )
        XCTAssertFalse(
            DesktopPetBehaviorEngine.shouldPauseRoaming(for: .running, activity: .agentMessage)
        )
        XCTAssertTrue(
            DesktopPetBehaviorEngine.shouldPauseRoaming(for: .running, activity: .reasoning)
        )
        XCTAssertTrue(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .waitingForInput))
        XCTAssertTrue(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .readyForReview))
        XCTAssertTrue(DesktopPetBehaviorEngine.shouldPauseRoaming(for: .error))
    }

    func testPetAnimationFrameRatesUseCalmerCadence() {
        XCTAssertEqual(PetAnimation.talkWalk.fps, 6)
        XCTAssertEqual(PetAnimation.outputBurst.fps, 6)
        XCTAssertLessThanOrEqual(PetAnimation.idleBreathe.fps, 5)
        XCTAssertLessThanOrEqual(PetAnimation.awaitJump.fps, 7)
    }

    func testFurinaFrameCacheKeyIncludesForm() {
        XCTAssertNotEqual(
            FurinaPetFrameKey(state: .idle, column: 0, form: .original),
            FurinaPetFrameKey(state: .idle, column: 0, form: .fullPink)
        )
    }

    func testFurinaRecolorChangesOpaquePixelsWithoutChangingTransparentMask() {
        guard let original = FurinaPetAtlas.shared.image(for: .idle, frame: 0, form: .original),
              let fullPink = FurinaPetAtlas.shared.image(for: .idle, frame: 0, form: .fullPink),
              let originalData = rgbaData(from: original),
              let fullPinkData = rgbaData(from: fullPink) else {
            XCTFail("Expected Furina frames to render")
            return
        }

        XCTAssertGreaterThan(differentOpaquePixelCount(originalData, fullPinkData), 100)
        XCTAssertEqual(transparentPixelCount(originalData), transparentPixelCount(fullPinkData))
    }

    func testFurinaHairStageDiffersFromHatStage() {
        guard let hat = FurinaPetAtlas.shared.image(for: .idle, frame: 0, form: .hatPink),
              let hair = FurinaPetAtlas.shared.image(for: .idle, frame: 0, form: .hairPink),
              let hatData = rgbaData(from: hat),
              let hairData = rgbaData(from: hair) else {
            XCTFail("Expected Furina frames to render")
            return
        }

        XCTAssertGreaterThan(differentOpaquePixelCount(hatData, hairData), 20)
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

    func testIpcDecoderRecognizesTokenContextUsage() {
        let line = """
        {"session_id":"sess-1","session_file":"/tmp/sess-1.jsonl","delta_input":10,"delta_cached_input":4,"delta_uncached_input":6,"delta_output":2,"delta_reasoning":1,"total_input":120,"total_cached_input":40,"total_uncached_input":80,"total_output":12,"total_reasoning":3,"context_used":154630,"context_window":258400,"cache_hit_rate":0.333333,"timestamp":"2026-07-01T08:00:00Z","turn_index":1}
        """

        switch IpcEventDecoder().decode(line: line) {
        case .token(let snapshot):
            XCTAssertEqual(snapshot.contextUsed, 154630)
            XCTAssertEqual(snapshot.contextWindow, 258400)
            XCTAssertEqual(snapshot.contextUsagePercent, "59.8%")
        default:
            XCTFail("Expected token snapshot")
        }
    }

    func testTokenContextUsageFallsBackToDefaultWindow() {
        let line = """
        {"session_id":"sess-1","session_file":"/tmp/sess-1.jsonl","delta_input":10,"delta_cached_input":4,"delta_uncached_input":6,"delta_output":2,"delta_reasoning":1,"total_input":120,"total_cached_input":40,"total_uncached_input":80,"total_output":12,"total_reasoning":3,"context_used":129200,"cache_hit_rate":0.333333,"timestamp":"2026-07-01T08:00:00Z","turn_index":1}
        """

        switch IpcEventDecoder().decode(line: line) {
        case .token(let snapshot):
            XCTAssertNil(snapshot.contextWindow)
            XCTAssertEqual(snapshot.contextUsagePercent, "50.0%")
        default:
            XCTFail("Expected token snapshot")
        }
    }

    func testSessionStateDecoderRecognizesRuntimeActivityAndTurn() throws {
        let line = """
        {"session_id":"thread-1","state":"running","activity_kind":"file_change","turn_state":"in_progress","source":"app_server","timestamp":"2026-07-01T08:00:00Z","await_reason":null}
        """

        switch IpcEventDecoder().decode(line: line) {
        case .state(let event):
            XCTAssertEqual(event.sessionId, "thread-1")
            XCTAssertEqual(event.state, .running)
            XCTAssertEqual(event.activityKind, .fileChange)
            XCTAssertEqual(event.turnState, .inProgress)
            XCTAssertEqual(event.source, .appServer)
        default:
            XCTFail("Expected session state event")
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

    private func rgbaData(from image: NSImage) -> [UInt8]? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var data = [UInt8](repeating: 0, count: bytesPerRow * height)

        let didDraw = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return didDraw ? data : nil
    }

    private func transparentPixelCount(_ data: [UInt8]) -> Int {
        stride(from: 3, to: data.count, by: 4)
            .filter { data[$0] == 0 }
            .count
    }

    private func differentOpaquePixelCount(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        let count = min(lhs.count, rhs.count)
        var changed = 0
        var index = 0

        while index + 3 < count {
            if lhs[index + 3] > 0 || rhs[index + 3] > 0 {
                let delta = abs(Int(lhs[index]) - Int(rhs[index]))
                    + abs(Int(lhs[index + 1]) - Int(rhs[index + 1]))
                    + abs(Int(lhs[index + 2]) - Int(rhs[index + 2]))
                if delta > 18 {
                    changed += 1
                }
            }
            index += 4
        }

        return changed
    }
}
