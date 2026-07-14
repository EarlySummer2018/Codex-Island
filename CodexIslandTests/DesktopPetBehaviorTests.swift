import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
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

    func testIslandInteractionHitAreasPrioritizeHeaderControlsThenHeaderDrag() {
        let expandedBounds = CGRect(x: 0, y: 0, width: 440, height: 290)
        let controlsFrame = IslandInteractionHitTest.headerControlsFrame(
            in: expandedBounds,
            isFlipped: true
        )

        XCTAssertEqual(
            IslandInteractionHitTest.region(
                for: CGPoint(x: controlsFrame.maxX - 22, y: controlsFrame.midY),
                in: expandedBounds,
                isFlipped: true
            ),
            .headerControls
        )
        XCTAssertEqual(
            IslandInteractionHitTest.region(
                for: CGPoint(x: controlsFrame.minX + 56, y: controlsFrame.midY),
                in: expandedBounds,
                isFlipped: true
            ),
            .headerControls
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

    func testAppRelauncherPassesBundlePathAsASeparateShellArgument() {
        let bundleURL = URL(fileURLWithPath: "/tmp/Codex Island's Build/CodexIsland.app")
        let arguments = AppRelauncher.helperArguments(for: bundleURL)

        XCTAssertEqual(arguments.first, "-c")
        XCTAssertEqual(arguments[2], "codex-island-restart")
        XCTAssertEqual(arguments[3], bundleURL.standardizedFileURL.path)
        XCTAssertFalse(arguments[1].contains(bundleURL.path))
        XCTAssertTrue(arguments[1].contains("open -n"))
    }

    func testIslandPressGestureSeparatesClickFromDrag() {
        let start = CGPoint(x: 40, y: 40)

        XCTAssertTrue(IslandPressGesture.isClick(from: start, to: CGPoint(x: 42, y: 43)))
        XCTAssertFalse(IslandPressGesture.isClick(from: start, to: CGPoint(x: 45, y: 40)))
        XCTAssertTrue(IslandPressGesture.isDrag(from: start, to: CGPoint(x: 45, y: 40)))
    }

    func testCapsuleSavedPositionPreservesTopCenterAcrossSizeChanges() {
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

        XCTAssertEqual(position.reference, .topCenter)
        XCTAssertEqual(
            restoredOrigin.x + compactSize.width / 2,
            expandedFrame.midX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            restoredOrigin.y + compactSize.height,
            expandedFrame.maxY,
            accuracy: 0.001
        )
    }

    func testIslandWindowGeometryPreservesAnchorAcrossRepeatedShapeChanges() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 720,
            maxY: 980
        )
        let pillSizes = CapsuleDisplayStyle.allCases.flatMap { style in
            [
                style.pillSize(desktopPetEnabled: false),
                style.pillSize(desktopPetEnabled: true)
            ]
        }

        for pillSize in pillSizes {
            for _ in 0..<50 {
                let expandedFrame = IslandWindowGeometry.frame(
                    size: IslandShape.expandedSize,
                    anchoredTo: anchor
                )
                let pillFrame = IslandWindowGeometry.frame(
                    size: pillSize,
                    anchoredTo: anchor
                )

                XCTAssertEqual(expandedFrame.midX, anchor.midX, accuracy: 0.001)
                XCTAssertEqual(expandedFrame.maxY, anchor.maxY, accuracy: 0.001)
                XCTAssertEqual(pillFrame.midX, anchor.midX, accuracy: 0.001)
                XCTAssertEqual(pillFrame.maxY, anchor.maxY, accuracy: 0.001)
                XCTAssertEqual(
                    pillFrame.minX - expandedFrame.minX,
                    (IslandShape.expandedSize.width - pillSize.width) / 2,
                    accuracy: 0.001
                )
            }
        }
    }

    @MainActor
    func testHostingSizingPolicyKeepsCompactFrameAfterAppKitLayout() async {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        let compactFrame = IslandWindowGeometry.frame(
            size: IslandShape.fallbackCompactSize,
            anchoredTo: anchor
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 324, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let hostingView = NSHostingView(
            rootView: Color.black.frame(width: 324, height: 34)
        )
        IslandHostingSizingPolicy.configure(hostingView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        panel.setFrame(compactFrame, display: false)
        panel.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(panel.frame.width, 120, accuracy: 0.5)
        XCTAssertEqual(panel.frame.midX, anchor.midX, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, anchor.maxY, accuracy: 0.5)
        XCTAssertFalse(
            IslandWindowGeometry.needsCorrection(
                actual: panel.frame,
                target: compactFrame
            )
        )
        panel.orderOut(nil)
    }

    func testScreenChangePreservesOrClampsExistingAnchor() {
        var anchorState = IslandWindowAnchorState()
        let original = anchorState.resolve(
            screenIdentifier: "display-1",
            restingFrame: CGRect(x: 478, y: 866, width: 324, height: 34)
        )
        let roomyFrame = CGRect(x: 0, y: 0, width: 1920, height: 1050)

        anchorState.preserveForScreenChange(
            usableFrame: roomyFrame,
            currentSize: CGSize(width: 324, height: 34)
        )
        XCTAssertEqual(anchorState.anchor, original)

        let reducedFrame = CGRect(x: 0, y: 0, width: 600, height: 500)
        anchorState.preserveForScreenChange(
            usableFrame: reducedFrame,
            currentSize: CGSize(width: 440, height: 290)
        )

        XCTAssertEqual(anchorState.anchor?.screenIdentifier, "display-1")
        XCTAssertEqual(anchorState.anchor?.midX ?? 0, 380, accuracy: 0.001)
        XCTAssertEqual(anchorState.anchor?.maxY ?? 0, 500, accuracy: 0.001)
    }

    func testFrameCorrectionDetectsHostingWidthRegression() {
        let target = CGRect(x: 580, y: 866, width: 120, height: 34)
        let regressed = CGRect(x: 580, y: 866, width: 324, height: 34)

        XCTAssertTrue(
            IslandWindowGeometry.needsCorrection(
                actual: regressed,
                target: target
            )
        )
        XCTAssertFalse(
            IslandWindowGeometry.needsCorrection(
                actual: target.offsetBy(dx: 0.25, dy: -0.25),
                target: target
            )
        )
    }

    func testIslandAnchorLifecycleOnlyChangesForApprovedPositionEvents() {
        var anchorState = IslandWindowAnchorState()
        let initialRestingFrame = CGRect(x: 500, y: 700, width: 324, height: 34)
        let initialAnchor = anchorState.resolve(
            screenIdentifier: "display-1",
            restingFrame: initialRestingFrame
        )

        XCTAssertFalse(anchorState.needsResolution(for: "display-1"))
        XCTAssertEqual(anchorState.anchor, initialAnchor)

        for size in [
            IslandShape.expandedSize,
            IslandShape.fallbackCompactSize,
            CGSize(width: 112, height: 34),
            CGSize(width: 360, height: 34)
        ] {
            _ = IslandWindowGeometry.frame(size: size, anchoredTo: initialAnchor)
            XCTAssertEqual(anchorState.anchor, initialAnchor)
        }

        let draggedFrame = CGRect(x: 760, y: 520, width: 440, height: 290)
        let draggedAnchor = anchorState.updateAfterDrag(
            screenIdentifier: "display-1",
            frame: draggedFrame
        )
        XCTAssertEqual(draggedAnchor.midX, draggedFrame.midX, accuracy: 0.001)
        XCTAssertEqual(draggedAnchor.maxY, draggedFrame.maxY, accuracy: 0.001)
        XCTAssertNotEqual(draggedAnchor, initialAnchor)

        anchorState.invalidate()
        XCTAssertNil(anchorState.anchor)
        XCTAssertTrue(anchorState.needsResolution(for: "display-1"))

        let resetFrame = CGRect(x: 798, y: 900, width: 324, height: 34)
        let resetAnchor = anchorState.resolve(
            screenIdentifier: "display-1",
            restingFrame: resetFrame
        )
        XCTAssertEqual(resetAnchor.midX, resetFrame.midX, accuracy: 0.001)
        XCTAssertEqual(resetAnchor.maxY, resetFrame.maxY, accuracy: 0.001)
    }

    func testIslandAnchorAndScreenSelectionFollowDisplayConfigurationChanges() {
        var anchorState = IslandWindowAnchorState()
        _ = anchorState.resolve(
            screenIdentifier: "display-1",
            restingFrame: CGRect(x: 500, y: 700, width: 324, height: 34)
        )

        XCTAssertEqual(
            IslandScreenSelection.preferredIdentifier(
                availableIdentifiers: ["display-1", "display-2"],
                anchorIdentifier: anchorState.anchor?.screenIdentifier,
                savedIdentifier: "display-2",
                primaryIdentifier: "display-1"
            ),
            "display-1"
        )

        anchorState.invalidate()
        XCTAssertEqual(
            IslandScreenSelection.preferredIdentifier(
                availableIdentifiers: ["display-1", "display-2"],
                anchorIdentifier: anchorState.anchor?.screenIdentifier,
                savedIdentifier: "display-2",
                primaryIdentifier: "display-1"
            ),
            "display-2"
        )

        XCTAssertEqual(
            IslandScreenSelection.preferredIdentifier(
                availableIdentifiers: ["display-2"],
                anchorIdentifier: "display-1",
                savedIdentifier: nil,
                primaryIdentifier: "display-2"
            ),
            "display-2"
        )

        let secondScreenAnchor = anchorState.resolve(
            screenIdentifier: "display-2",
            restingFrame: CGRect(x: 2400, y: 820, width: 324, height: 34)
        )
        XCTAssertEqual(secondScreenAnchor.screenIdentifier, "display-2")
        XCTAssertFalse(anchorState.needsResolution(for: "display-2"))
        XCTAssertTrue(anchorState.needsResolution(for: "display-1"))
    }

    func testLegacyCenterSavedPositionStillRestoresWithoutMigrationLoss() {
        let usableFrame = CGRect(x: 0, y: 100, width: 1000, height: 700)
        let legacyPosition = SavedIslandPosition(
            xRatio: 0.62,
            yRatio: 0.74,
            reference: .center
        )
        let size = CGSize(width: 324, height: 34)

        let origin = IslandPositionGeometry.origin(
            for: size,
            usableFrame: usableFrame,
            position: legacyPosition
        )

        XCTAssertEqual(origin.x + size.width / 2, 620, accuracy: 0.001)
        XCTAssertEqual(origin.y + size.height / 2, 618, accuracy: 0.001)
    }

    func testSessionStateChangesKeepConfiguredPillSizeAndAnchor() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        let states: [CodexSessionState] = [.running, .notLoaded, .running]
        let configuredSize = CGSize(width: 324, height: 34)
        var transitionState = IslandWindowTransitionState(restingShape: .pill)

        for _ in states {
            transitionState.setCurrentShape(.pill)
            let transition = transitionState.beginTransition(
                size: configuredSize,
                anchoredTo: anchor
            )

            XCTAssertEqual(transition.targetShape, .pill)
            XCTAssertEqual(transition.targetFrame.size, configuredSize)
            XCTAssertEqual(transition.targetFrame.midX, anchor.midX, accuracy: 0.001)
            XCTAssertEqual(transition.targetFrame.maxY, anchor.maxY, accuracy: 0.001)
            XCTAssertEqual(
                transitionState.settledPresentationState(
                    for: transition.id,
                    isDragging: false,
                    isPressingForDrag: false
                ),
                .collapsed
            )
        }
    }

    func testCapsuleStyleChangeSettlesExpandedWindowAtNewPillSizeImmediately() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        var transitionState = IslandWindowTransitionState(restingShape: .pill)
        XCTAssertTrue(transitionState.activateExpansion(for: .hover))

        transitionState.deactivateExpansion()
        let smallSize = CapsuleDisplayStyle.small.pillSize(desktopPetEnabled: true)
        let transition = transitionState.beginTransition(size: smallSize, anchoredTo: anchor)

        XCTAssertFalse(transitionState.isExpansionActive)
        XCTAssertEqual(transition.targetShape, .pill)
        XCTAssertEqual(transition.targetFrame.width, 112, accuracy: 0.001)
        XCTAssertEqual(transition.targetFrame.midX, anchor.midX, accuracy: 0.001)
    }

    func testOutOfOrderExpansionAndCollapseCompletionsOnlySettleLatestTransition() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        var transitionState = IslandWindowTransitionState(restingShape: .pill)

        transitionState.activateExpansion(for: .hover)
        let firstExpansion = transitionState.beginTransition(
            size: IslandShape.expandedSize,
            anchoredTo: anchor
        )
        transitionState.deactivateExpansion()
        let interruptedCollapse = transitionState.beginTransition(
            size: CGSize(width: 324, height: 34),
            anchoredTo: anchor
        )
        transitionState.activateExpansion(for: .hover)
        let latestExpansion = transitionState.beginTransition(
            size: IslandShape.expandedSize,
            anchoredTo: anchor
        )

        for staleTransition in [interruptedCollapse, firstExpansion] {
            XCTAssertNil(
                transitionState.settledPresentationState(
                    for: staleTransition.id,
                    isDragging: false,
                    isPressingForDrag: false
                )
            )
        }
        XCTAssertEqual(
            transitionState.settledPresentationState(
                for: latestExpansion.id,
                isDragging: false,
                isPressingForDrag: false
            ),
            .expanded
        )

        transitionState.deactivateExpansion()
        let latestCollapse = transitionState.beginTransition(
            size: CGSize(width: 324, height: 34),
            anchoredTo: anchor
        )

        XCTAssertNil(
            transitionState.settledPresentationState(
                for: latestExpansion.id,
                isDragging: false,
                isPressingForDrag: false
            )
        )
        XCTAssertEqual(
            transitionState.settledPresentationState(
                for: latestCollapse.id,
                isDragging: false,
                isPressingForDrag: false
            ),
            .collapsed
        )
    }

    func testIslandContentPresentationSettlesAfterInterruptedDrag() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        var transitionState = IslandWindowTransitionState(restingShape: .pill)
        transitionState.activateExpansion(for: .hover)
        let expansion = transitionState.beginTransition(
            size: IslandShape.expandedSize,
            anchoredTo: anchor
        )

        transitionState.invalidateTransitions()

        XCTAssertNil(
            transitionState.settledPresentationState(
                for: expansion.id,
                isDragging: true,
                isPressingForDrag: true
            )
        )

        XCTAssertNil(
            transitionState.settledPresentationState(
                for: expansion.id,
                isDragging: false,
                isPressingForDrag: false
            )
        )

        let resumedExpansion = transitionState.beginTransition(
            size: IslandShape.expandedSize,
            anchoredTo: anchor
        )
        XCTAssertEqual(
            transitionState.settledPresentationState(
                for: resumedExpansion.id,
                isDragging: false,
                isPressingForDrag: false
            ),
            .expanded
        )

        transitionState.deactivateExpansion()
        let collapse = transitionState.beginTransition(
            size: CGSize(width: 324, height: 34),
            anchoredTo: anchor
        )
        XCTAssertEqual(
            transitionState.settledPresentationState(
                for: collapse.id,
                isDragging: false,
                isPressingForDrag: false
            ),
            .collapsed
        )
        XCTAssertNil(
            transitionState.settledPresentationState(
                for: resumedExpansion.id,
                isDragging: false,
                isPressingForDrag: false
            )
        )
    }

    func testExpandedPanelAlwaysCollapsesToConfiguredPill() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        var transitionState = IslandWindowTransitionState(restingShape: .pill)
        transitionState.activateExpansion(for: .hover)
        let expansion = transitionState.beginTransition(
            size: IslandShape.expandedSize,
            anchoredTo: anchor
        )

        XCTAssertEqual(transitionState.currentShape, .expanded)
        XCTAssertEqual(transitionState.restingShape, .pill)
        XCTAssertEqual(
            transitionState.settledPresentationState(
                for: expansion.id,
                isDragging: false,
                isPressingForDrag: false
            ),
            .expanded
        )

        transitionState.deactivateExpansion()
        let collapse = transitionState.beginTransition(
            size: CGSize(width: 324, height: 34),
            anchoredTo: anchor
        )

        XCTAssertEqual(collapse.targetShape, .pill)
        XCTAssertEqual(collapse.targetFrame.midX, expansion.targetFrame.midX, accuracy: 0.001)
        XCTAssertEqual(collapse.targetFrame.maxY, expansion.targetFrame.maxY, accuracy: 0.001)
        XCTAssertNil(
            transitionState.settledPresentationState(
                for: expansion.id,
                isDragging: false,
                isPressingForDrag: false
            )
        )
        XCTAssertEqual(
            transitionState.settledPresentationState(
                for: collapse.id,
                isDragging: false,
                isPressingForDrag: false
            ),
            .collapsed
        )
    }

    func testHoverAndClickExpansionShareFixedAnchorSemantics() {
        let anchor = IslandWindowAnchor(
            screenIdentifier: "display-1",
            midX: 640,
            maxY: 900
        )
        var expandedFrames: [NSRect] = []
        var collapsedFrames: [NSRect] = []

        for trigger in CapsuleExpansionTrigger.allCases {
            var transitionState = IslandWindowTransitionState(restingShape: .pill)
            XCTAssertTrue(transitionState.activateExpansion(for: trigger))
            let expansion = transitionState.beginTransition(
                size: IslandShape.expandedSize,
                anchoredTo: anchor
            )
            transitionState.deactivateExpansion()
            let collapse = transitionState.beginTransition(
                size: CGSize(width: 324, height: 34),
                anchoredTo: anchor
            )

            XCTAssertEqual(expansion.targetFrame.midX, anchor.midX, accuracy: 0.001)
            XCTAssertEqual(expansion.targetFrame.maxY, anchor.maxY, accuracy: 0.001)
            XCTAssertEqual(collapse.targetFrame.midX, anchor.midX, accuracy: 0.001)
            XCTAssertEqual(collapse.targetFrame.maxY, anchor.maxY, accuracy: 0.001)
            expandedFrames.append(expansion.targetFrame)
            collapsedFrames.append(collapse.targetFrame)
        }

        XCTAssertEqual(expandedFrames.count, 2)
        XCTAssertEqual(collapsedFrames.count, 2)
        XCTAssertEqual(expandedFrames[0], expandedFrames[1])
        XCTAssertEqual(collapsedFrames[0], collapsedFrames[1])
    }

    func testConfiguredCapsuleSizeDoesNotDependOnSessionState() {
        let states: [CodexSessionState] = [
            .notLoaded,
            .idle,
            .running,
            .waitingForInput,
            .readyForReview,
            .error
        ]

        for _ in states {
            XCTAssertEqual(
                IslandShape.pill.size(
                    fitting: CGRect(
                        origin: .zero,
                        size: IslandShape.fallbackCompactSize
                    ),
                    capsuleStyle: .large,
                    desktopPetEnabled: true
                ).width,
                324
            )
            XCTAssertEqual(
                IslandShape.pill.size(
                    fitting: CGRect(
                        origin: .zero,
                        size: IslandShape.fallbackCompactSize
                    ),
                    capsuleStyle: .small,
                    desktopPetEnabled: true
                ).width,
                112
            )
        }
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

    func testPetAtlasGeometryMatchesCodexPetsContract() {
        XCTAssertEqual(PetAtlasSpec.columns, 8)
        XCTAssertEqual(PetAtlasSpec.rows, 9)
        XCTAssertEqual(PetAtlasSpec.cellWidth, 192)
        XCTAssertEqual(PetAtlasSpec.cellHeight, 208)
        XCTAssertEqual(PetAtlasSpec.atlasWidth, 1536)
        XCTAssertEqual(PetAtlasSpec.atlasHeight, 1872)
    }

    func testFurinaSpritesheetDataAssetIsBundled() {
        guard let dataAsset = NSDataAsset(name: PetAtlasRepository.bundledAssetName) else {
            XCTFail("Expected bundled Furina spritesheet data asset")
            return
        }

        guard let imageSource = CGImageSourceCreateWithData(dataAsset.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            XCTFail("Expected Furina spritesheet WebP to decode")
            return
        }

        XCTAssertEqual(image.width, PetAtlasSpec.atlasWidth)
        XCTAssertEqual(image.height, PetAtlasSpec.atlasHeight)
    }

    func testPetAnimationsMapToAtlasRows() {
        XCTAssertEqual(PetAnimation.idleBreathe.petAtlasState, .idle)
        XCTAssertEqual(PetAnimation.bubbleThink.petAtlasState, .review)
        XCTAssertEqual(PetAnimation.talkWalk.petAtlasState, .running)
        XCTAssertEqual(PetAnimation.outputBurst.petAtlasState, .running)
        XCTAssertEqual(PetAnimation.awaitJump.petAtlasState, .waiting)
        XCTAssertEqual(PetAnimation.errorFall.petAtlasState, .failed)
        XCTAssertEqual(PetAnimation.dragHover.petAtlasState, .jumping)
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

    func testDirectionalMovementUsesLeftAndRightRows() {
        XCTAssertEqual(PetAnimation.talkWalk.petAtlasState(facingLeft: nil), .runningRight)
        XCTAssertEqual(PetAnimation.talkWalk.petAtlasState(facingLeft: false), .runningRight)
        XCTAssertEqual(PetAnimation.talkWalk.petAtlasState(facingLeft: true), .runningLeft)
        XCTAssertEqual(PetAnimation.outputBurst.petAtlasState(facingLeft: nil), .runningRight)
        XCTAssertEqual(PetAnimation.outputBurst.petAtlasState(facingLeft: false), .runningRight)
        XCTAssertEqual(PetAnimation.idleBreathe.petAtlasState(facingLeft: true), .idle)
    }

    func testPetFrameIndexWrapsToAtlasColumns() {
        XCTAssertEqual(PetAtlasSpec.visibleColumnCount(for: .idle), 6)
        XCTAssertEqual(PetAtlasSpec.visibleColumnCount(for: .waving), 4)
        XCTAssertEqual(PetAtlasSpec.visibleColumnCount(for: .jumping), 5)
        XCTAssertEqual(PetAtlasSpec.visibleColumnCount(for: .runningRight), 8)

        XCTAssertEqual(PetAtlasSpec.normalizedFrameIndex(5, for: .idle), 5)
        XCTAssertEqual(PetAtlasSpec.normalizedFrameIndex(6, for: .idle), 0)
        XCTAssertEqual(PetAtlasSpec.normalizedFrameIndex(7, for: .waving), 3)
        XCTAssertEqual(PetAtlasSpec.normalizedFrameIndex(8, for: .runningRight), 0)
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

    func testBundledPetFrameCacheKeyIncludesForm() {
        XCTAssertNotEqual(
            PetFrameKey(state: .idle, column: 0, source: .bundled(.original)),
            PetFrameKey(state: .idle, column: 0, source: .bundled(.fullPink))
        )
    }

    func testFurinaRecolorChangesOpaquePixelsWithoutChangingTransparentMask() {
        let repository = makeBundledPetRepository()
        guard let original = repository.image(for: .idle, frame: 0, form: .original),
              let fullPink = repository.image(for: .idle, frame: 0, form: .fullPink),
              let originalData = rgbaData(from: original),
              let fullPinkData = rgbaData(from: fullPink) else {
            XCTFail("Expected Furina frames to render")
            return
        }

        XCTAssertGreaterThan(differentOpaquePixelCount(originalData, fullPinkData), 100)
        XCTAssertEqual(transparentPixelCount(originalData), transparentPixelCount(fullPinkData))
    }

    func testFurinaHairStageDiffersFromHatStage() {
        let repository = makeBundledPetRepository()
        guard let hat = repository.image(for: .idle, frame: 0, form: .hatPink),
              let hair = repository.image(for: .idle, frame: 0, form: .hairPink),
              let hatData = rgbaData(from: hat),
              let hairData = rgbaData(from: hair) else {
            XCTFail("Expected Furina frames to render")
            return
        }

        XCTAssertGreaterThan(differentOpaquePixelCount(hatData, hairData), 20)
    }

    func testIpcDecoderRecognizesDailyTokenUsage() {
        let line = """
        {"type":"daily_token_usage","local_date":"2026-07-01","total_input":120,"total_cached_input":30,"total_output":45,"total_reasoning":5,"total_tokens":165,"session_count":3,"request_count":17,"updated_at":"2026-07-01T08:00:00Z"}
        """

        switch IpcEventDecoder().decode(line: line) {
        case .dailyToken(let snapshot):
            XCTAssertEqual(snapshot.localDate, "2026-07-01")
            XCTAssertEqual(snapshot.totalTokens, 165)
            XCTAssertEqual(snapshot.sessionCount, 3)
            XCTAssertEqual(snapshot.requestCount, 17)
        default:
            XCTFail("Expected daily token snapshot")
        }
    }

    @MainActor
    func testTokenStoreKeepsActiveSessionAndMachineTotalsSeparate() {
        let store = TokenStore.shared
        store.reset()
        let global = GlobalTokenUsageSnapshot(
            type: "global_token_usage",
            totalInput: 1_000,
            totalCachedInput: 750,
            totalOutput: 100,
            totalReasoning: 20,
            totalTokens: 1_100,
            sessionCount: 4,
            updatedAt: Date()
        )
        store.update(with: global)
        store.update(with: tokenSnapshot(
            sessionId: "active-session",
            totalInput: 200,
            timestamp: Date()
        ))

        XCTAssertEqual(store.totalInput, 200)
        XCTAssertEqual(store.globalTotalInput, 1_000)
        XCTAssertEqual(store.globalTotalCachedInput, 750)
        XCTAssertEqual(store.globalTotalOutput, 100)
        XCTAssertEqual(store.globalTotalTokens, 1_100)
        XCTAssertEqual(store.globalCacheHitPercent, "75.0%")
        store.reset()
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

    @MainActor
    func testAbortedSessionNoLongerWinsAsRunning() {
        TokenStore.shared.reset()
        let bus = EventBus(minimumActiveDisplayDuration: 0)
        let startedAt = Date(timeIntervalSince1970: 100)

        bus.handleStateEvent(SessionStateEvent(
            sessionId: "stale-subagent",
            state: .running,
            activityKind: .fileChange,
            turnState: .inProgress,
            source: .jsonl,
            timestamp: startedAt
        ))
        bus.handleStateEvent(SessionStateEvent(
            sessionId: "finished-main",
            state: .idle,
            turnState: .completed,
            source: .jsonl,
            timestamp: startedAt.addingTimeInterval(1)
        ))

        XCTAssertEqual(bus.activeSessionId, "stale-subagent")
        XCTAssertEqual(bus.sessionState, .running)

        bus.handleStateEvent(SessionStateEvent(
            sessionId: "stale-subagent",
            state: .idle,
            turnState: .interrupted,
            source: .jsonl,
            timestamp: startedAt.addingTimeInterval(2)
        ))

        XCTAssertEqual(bus.sessionState, .idle)
        XCTAssertEqual(bus.activityKind, .none)
        XCTAssertEqual(bus.turnState, .interrupted)
        TokenStore.shared.reset()
    }

    @MainActor
    func testRuntimeDisconnectClearsStateButPreservesToken() {
        TokenStore.shared.reset()
        let bus = EventBus(minimumActiveDisplayDuration: 0)
        let snapshot = tokenSnapshot(sessionId: "session-a", totalInput: 120, timestamp: Date())

        bus.handleTokenSnapshot(snapshot)
        bus.handleStateEvent(SessionStateEvent(
            sessionId: "session-a",
            state: .running,
            activityKind: .commandExecution,
            turnState: .inProgress,
            source: .appServer,
            timestamp: snapshot.timestamp
        ))
        bus.handleRuntimeDisconnected()

        XCTAssertEqual(bus.activeSessionId, "session-a")
        XCTAssertEqual(bus.sessionState, .notLoaded)
        XCTAssertEqual(bus.activityKind, .none)
        XCTAssertNil(bus.turnState)
        XCTAssertEqual(bus.latestToken?.totalInput, 120)
        TokenStore.shared.reset()
    }

    @MainActor
    func testTokenSelectionRefreshesStateAndTokenTogether() {
        TokenStore.shared.reset()
        let bus = EventBus(minimumActiveDisplayDuration: 0)
        let base = Date(timeIntervalSince1970: 200)

        bus.handleStateEvent(SessionStateEvent(
            sessionId: "session-a",
            state: .idle,
            turnState: .completed,
            source: .jsonl,
            timestamp: base
        ))
        bus.handleTokenSnapshot(tokenSnapshot(
            sessionId: "session-a",
            totalInput: 100,
            timestamp: base
        ))
        bus.handleStateEvent(SessionStateEvent(
            sessionId: "session-b",
            state: .idle,
            turnState: .completed,
            source: .jsonl,
            timestamp: base.addingTimeInterval(1)
        ))
        bus.handleTokenSnapshot(tokenSnapshot(
            sessionId: "session-b",
            totalInput: 200,
            timestamp: base.addingTimeInterval(2)
        ))

        XCTAssertEqual(bus.activeSessionId, "session-b")
        XCTAssertEqual(bus.sessionState, .idle)
        XCTAssertEqual(bus.latestToken?.sessionId, "session-b")
        XCTAssertEqual(bus.latestToken?.totalInput, 200)
        TokenStore.shared.reset()
    }

    private func tokenSnapshot(sessionId: String, totalInput: Int, timestamp: Date) -> TokenSnapshot {
        TokenSnapshot(
            sessionId: sessionId,
            sessionFile: "/tmp/\(sessionId).jsonl",
            deltaInput: totalInput,
            deltaCachedInput: 0,
            deltaUncachedInput: totalInput,
            deltaOutput: 1,
            deltaReasoning: 0,
            totalInput: totalInput,
            totalCachedInput: 0,
            totalUncachedInput: totalInput,
            totalOutput: 1,
            totalReasoning: 0,
            contextUsed: nil,
            contextWindow: nil,
            cacheHitRate: 0,
            timestamp: timestamp,
            turnIndex: 1
        )
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

    private func makeBundledPetRepository() -> PetAtlasRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexIslandBundledPetTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return PetAtlasRepository(catalog: CustomPetCatalog(rootDirectory: root))
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
