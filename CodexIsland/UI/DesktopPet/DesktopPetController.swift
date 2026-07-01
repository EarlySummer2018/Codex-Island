import AppKit
import Combine
import CoreGraphics

@MainActor
final class DesktopPetController: ObservableObject {
    static let shared = DesktopPetController()

    @Published private(set) var phase: DesktopPetPhase = .disabled
    @Published private(set) var action: DesktopPetAction = .idle
    @Published private(set) var animationName: PetAnimation = .idleBreathe
    @Published private(set) var isFacingLeft = false
    @Published private(set) var presentationScale = DesktopPetMetrics.desktopPresentationScale

    let windowSize = DesktopPetMetrics.windowSize
    let petSize = DesktopPetMetrics.petSize

    private let settings = AppSettingsStore.shared
    private let eventBus = EventBus.shared
    private var panelStorage: DesktopPetPanel?
    private var cancellables = Set<AnyCancellable>()
    private var scheduledWorkItem: DispatchWorkItem?
    private var movementID = 0
    private var isConfigured = false
    private var dragOffsetInWindow = CGPoint(
        x: DesktopPetMetrics.windowSize.width / 2,
        y: DesktopPetMetrics.windowSize.height * 0.62
    )
    private var lastDragScreenLocation: CGPoint?

    private init() {}

    func configure() {
        guard !isConfigured else {
            return
        }

        isConfigured = true

        settings.$isDesktopPetEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self else {
                    return
                }

                if enabled {
                    self.enable()
                } else {
                    self.disable(animated: true)
                }
            }
            .store(in: &cancellables)

        settings.$isCapsuleVisible
            .dropFirst()
            .sink { [weak self] visible in
                guard let self else {
                    return
                }

                if !visible {
                    self.stopImmediately()
                }
            }
            .store(in: &cancellables)

        eventBus.$sessionState
            .dropFirst()
            .sink { [weak self] state in
                self?.reactToSessionState(state)
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if settings.isDesktopPetEnabled {
            enable()
        }
    }

    func stopImmediately() {
        cancelScheduledWork()
        movementID += 1
        phase = .disabled
        action = .idle
        animationName = .idleBreathe
        presentationScale = DesktopPetMetrics.desktopPresentationScale
        panelStorage?.orderOut(nil)
    }

    func handleClick(clickCount: Int, screenLocation: CGPoint) {
        guard phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning,
              phase != .dragging else {
            return
        }

        cancelScheduledWork()
        movementID += 1
        phase = .dodging
        action = .dodging
        animationName = .startledHop

        let reactionID = movementID
        runAfter(0.18) { [weak self] in
            guard let self, self.movementID == reactionID, self.phase == .dodging else {
                return
            }

            self.startDodge(from: screenLocation, clickCount: clickCount)
        }
    }

    func handleDragBegan(screenLocation: CGPoint, offsetInWindow: CGPoint) {
        guard phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning else {
            return
        }

        cancelScheduledWork()
        movementID += 1
        phase = .dragging
        action = .dragging
        animationName = .dragHover
        dragOffsetInWindow = offsetInWindow
        lastDragScreenLocation = screenLocation
    }

    func handleDragChanged(screenLocation: CGPoint) {
        guard phase == .dragging else {
            return
        }

        if let previous = lastDragScreenLocation {
            updateFacing(from: previous, to: screenLocation)
        }
        lastDragScreenLocation = screenLocation

        let proposed = CGPoint(
            x: screenLocation.x - dragOffsetInWindow.x,
            y: screenLocation.y - dragOffsetInWindow.y
        )
        let clamped = DesktopPetBehaviorEngine.clampedOrigin(
            proposed,
            windowSize: windowSize,
            in: visibleFrames
        )
        panel.setFrame(NSRect(origin: clamped, size: windowSize), display: true)
    }

    func handleDragEnded(screenLocation: CGPoint) {
        guard phase == .dragging else {
            return
        }

        handleDragChanged(screenLocation: screenLocation)
        landAndResume()
    }

    private var panel: DesktopPetPanel {
        if let panelStorage {
            return panelStorage
        }

        let panel = DesktopPetPanel(controller: self)
        panelStorage = panel
        return panel
    }

    private func enable() {
        guard settings.isCapsuleVisible else {
            settings.isDesktopPetEnabled = false
            return
        }

        if phase == .waitingForCapsuleStill || phase == .returning {
            resumeFromReturnInterruption()
            return
        }

        cancelScheduledWork()
        movementID += 1

        let anchor = NotchIslandPanel.shared.desktopPetAnchorPoint()
        let startOrigin = DesktopPetBehaviorEngine.origin(
            centeredOn: anchor,
            windowSize: windowSize
        )
        let state = eventBus.sessionState

        phase = .launching
        action = .strolling
        animationName = movingAnimation(for: state)
        presentationScale = DesktopPetMetrics.capsulePresentationScale
        panel.setFrame(NSRect(origin: startOrigin, size: windowSize), display: true)
        panel.orderFrontRegardless()

        let target = DesktopPetBehaviorEngine.launchTarget(
            from: anchor,
            windowSize: windowSize,
            in: visibleFrames
        )
        let launchDuration = duration(
            to: target,
            speed: DesktopPetMetrics.launchSpeed,
            minimum: 0.85,
            maximum: 1.45
        )
        let launchID = movementID
        runAfter(0.02) { [weak self] in
            guard let self,
                  self.movementID == launchID,
                  self.phase == .launching else {
                return
            }

            self.presentationScale = DesktopPetMetrics.desktopPresentationScale
            self.movePanel(
                to: target,
                duration: launchDuration,
                phase: .launching,
                action: .strolling,
                animation: self.movingAnimation(for: state)
            ) { [weak self] in
                self?.landAndResume()
            }
        }
    }

    private func disable(animated: Bool) {
        guard phase != .disabled else {
            return
        }

        cancelScheduledWork()
        movementID += 1

        guard animated,
              settings.isCapsuleVisible,
              panelStorage?.isVisible == true else {
            stopImmediately()
            return
        }

        beginReturnWhenCapsuleIsStable()
    }

    private func resumeFromReturnInterruption() {
        cancelScheduledWork()
        movementID += 1

        let clamped = DesktopPetBehaviorEngine.clampedOrigin(
            currentOrigin,
            windowSize: windowSize,
            in: visibleFrames
        )
        panel.setFrame(NSRect(origin: clamped, size: windowSize), display: true)
        panel.orderFrontRegardless()

        let state = eventBus.sessionState
        phase = .roaming
        action = .pausing
        animationName = restingAnimation(for: state)
        presentationScale = DesktopPetMetrics.desktopPresentationScale

        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state) {
            applyStationaryState(state)
        } else {
            scheduleNextRoam(delay: 0.35)
        }
    }

    private func beginReturnWhenCapsuleIsStable() {
        cancelScheduledWork()
        let sequenceID = movementID
        phase = .waitingForCapsuleStill
        action = .lookingAround
        animationName = .idleBreathe
        presentationScale = DesktopPetMetrics.desktopPresentationScale

        waitForStableCapsuleAnchor(
            previousAnchor: nil,
            stableSince: nil,
            sequenceID: sequenceID
        )
    }

    private func waitForStableCapsuleAnchor(
        previousAnchor: CGPoint?,
        stableSince: Date?,
        sequenceID: Int
    ) {
        guard movementID == sequenceID,
              phase == .waitingForCapsuleStill,
              settings.isCapsuleVisible else {
            return
        }

        let anchor = NotchIslandPanel.shared.desktopPetAnchorPoint()
        let target = DesktopPetBehaviorEngine.returnOrigin(
            to: anchor,
            windowSize: windowSize
        )
        updateFacing(from: currentOrigin, to: target)

        let now = Date()
        let nextStableSince: Date?
        if let previousAnchor,
           DesktopPetBehaviorEngine.anchorsAreStable(previousAnchor, anchor) {
            let since = stableSince ?? now
            if now.timeIntervalSince(since) >= DesktopPetMetrics.capsuleAnchorStableDelay {
                returnToCapsule(anchor: anchor)
                return
            }

            nextStableSince = since
        } else {
            nextStableSince = nil
        }

        runAfter(DesktopPetMetrics.capsuleAnchorPollDelay) { [weak self] in
            self?.waitForStableCapsuleAnchor(
                previousAnchor: anchor,
                stableSince: nextStableSince,
                sequenceID: sequenceID
            )
        }
    }

    private func returnToCapsule(anchor: CGPoint) {
        guard phase == .waitingForCapsuleStill,
              settings.isCapsuleVisible else {
            return
        }

        let target = DesktopPetBehaviorEngine.returnOrigin(
            to: anchor,
            windowSize: windowSize
        )
        let returnDuration = duration(
            to: target,
            speed: DesktopPetMetrics.returnSpeed,
            minimum: 0.75,
            maximum: 1.85
        )

        presentationScale = DesktopPetMetrics.capsulePresentationScale
        movePanel(
            to: target,
            duration: returnDuration,
            phase: .returning,
            action: .returning,
            animation: .talkWalk
        ) { [weak self] in
            guard let self else {
                return
            }

            let latestAnchor = NotchIslandPanel.shared.desktopPetAnchorPoint()
            guard DesktopPetBehaviorEngine.anchorsAreStable(anchor, latestAnchor) else {
                self.beginReturnWhenCapsuleIsStable()
                return
            }

            self.stopImmediately()
        }
    }

    private func startDodge(from screenLocation: CGPoint, clickCount: Int) {
        let target = DesktopPetBehaviorEngine.dodgeTarget(
            from: currentOrigin,
            clickLocation: screenLocation,
            windowSize: windowSize,
            in: visibleFrames,
            clickCount: clickCount
        )
        let speed: CGFloat = clickCount >= 2 ? 280 : 220
        movePanel(
            to: target,
            duration: duration(to: target, speed: speed, minimum: 0.55, maximum: 1.85),
            phase: .dodging,
            action: .dodging,
            animation: .talkWalk
        ) { [weak self] in
            self?.landAndResume()
        }
    }

    private func startRoamStep() {
        guard settings.isDesktopPetEnabled,
              phase == .roaming else {
            return
        }

        let state = eventBus.sessionState
        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state) {
            applyStationaryState(state)
            return
        }

        let target = DesktopPetBehaviorEngine.roamingTarget(
            from: currentOrigin,
            windowSize: windowSize,
            in: visibleFrames,
            maxDistance: DesktopPetMetrics.maxRoamDistance
        )
        movePanel(
            to: target,
            duration: duration(to: target, speed: roamSpeed, minimum: 1.0, maximum: 4.8),
            phase: .roaming,
            action: .strolling,
            animation: movingAnimation(for: state)
        ) { [weak self] in
            guard let self, self.phase == .roaming else {
                return
            }

            self.playRestingMicroAction()
        }
    }

    private func landAndResume() {
        cancelScheduledWork()
        phase = .dropped
        action = .landing
        animationName = .landBounce

        runAfter(0.72) { [weak self] in
            self?.resumeRoaming()
        }
    }

    private func resumeRoaming() {
        guard settings.isDesktopPetEnabled,
              settings.isCapsuleVisible,
              phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning else {
            return
        }

        phase = .roaming
        action = .pausing
        applyRestingState(eventBus.sessionState)
        if !DesktopPetBehaviorEngine.shouldPauseRoaming(for: eventBus.sessionState) {
            scheduleNextRoam(delay: nextRoamDelay)
        }
    }

    private func reactToSessionState(_ state: CodexSessionState) {
        guard settings.isDesktopPetEnabled,
              phase == .roaming else {
            return
        }

        cancelScheduledWork()
        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state) {
            applyStationaryState(state, shouldFreezeCurrentMovement: action == .strolling)
            return
        }

        if action == .strolling {
            animationName = movingAnimation(for: state)
        } else {
            action = .pausing
            animationName = restingAnimation(for: state)
            scheduleNextRoam(delay: nextRoamDelay)
        }
    }

    private func playRestingMicroAction(delayOverride: TimeInterval? = nil) {
        guard settings.isDesktopPetEnabled,
              settings.isCapsuleVisible,
              phase == .roaming else {
            return
        }

        let state = eventBus.sessionState
        let selectedAction = microAction(for: state)
        action = selectedAction
        animationName = animation(for: selectedAction, state: state)
        scheduleNextRoam(delay: delayOverride ?? delay(for: selectedAction, state: state))
    }

    private func applyRestingState(_ state: CodexSessionState) {
        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state) && state == .awaitingInput {
            action = .hopping
        } else {
            action = .pausing
        }
        animationName = restingAnimation(for: state)
    }

    private func applyStationaryState(
        _ state: CodexSessionState,
        shouldFreezeCurrentMovement: Bool = false
    ) {
        cancelScheduledWork()
        if shouldFreezeCurrentMovement {
            freezeCurrentPanelMovement()
        }
        applyRestingState(state)
    }

    private func microAction(for state: CodexSessionState) -> DesktopPetAction {
        switch state {
        case .idle:
            return [.pausing, .lookingAround, .hopping].randomElement() ?? .pausing
        case .thinking, .working:
            return [.pausing, .lookingAround].randomElement() ?? .lookingAround
        case .streaming:
            return [.pausing, .hopping].randomElement() ?? .pausing
        case .awaitingInput:
            return .hopping
        case .error:
            return .pausing
        }
    }

    private func animation(
        for action: DesktopPetAction,
        state: CodexSessionState
    ) -> PetAnimation {
        switch action {
        case .hopping:
            return state == .awaitingInput ? restingAnimation(for: state) : .happyBounce
        case .lookingAround:
            return state == .thinking || state == .working ? restingAnimation(for: state) : .idleStretch
        case .pausing:
            return restingAnimation(for: state)
        case .landing:
            return .landBounce
        case .strolling, .dodging, .returning:
            return movingAnimation(for: state)
        case .dragging:
            return .dragHover
        case .idle:
            return restingAnimation(for: state)
        }
    }

    private func delay(
        for action: DesktopPetAction,
        state: CodexSessionState
    ) -> TimeInterval {
        switch action {
        case .hopping:
            return state == .streaming ? 1.2 : 1.8
        case .lookingAround:
            return 2.0
        case .pausing:
            return nextRoamDelay
        case .idle, .strolling, .dodging, .dragging, .landing, .returning:
            return nextRoamDelay
        }
    }

    @objc private func screenParametersChanged() {
        guard phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning else {
            return
        }

        let clamped = DesktopPetBehaviorEngine.clampedOrigin(
            currentOrigin,
            windowSize: windowSize,
            in: visibleFrames
        )
        panel.setFrame(NSRect(origin: clamped, size: windowSize), display: true)
    }

    private func movePanel(
        to target: CGPoint,
        duration: TimeInterval,
        phase nextPhase: DesktopPetPhase,
        action nextAction: DesktopPetAction,
        animation: PetAnimation,
        completion: (() -> Void)? = nil
    ) {
        cancelScheduledWork()
        movementID += 1
        let currentMovementID = movementID
        let origin = currentOrigin
        let clampedTarget = nextPhase == .returning
            ? target
            : DesktopPetBehaviorEngine.clampedOrigin(
                target,
                windowSize: windowSize,
                in: visibleFrames
            )

        updateFacing(from: origin, to: clampedTarget)
        phase = nextPhase
        action = nextAction
        animationName = animation

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NSRect(origin: clampedTarget, size: windowSize),
                display: true
            )
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.movementID == currentMovementID else {
                    return
                }

                completion?()
            }
        }
    }

    private func scheduleNextRoam(delay: TimeInterval) {
        cancelScheduledWork()
        let workItem = DispatchWorkItem { [weak self] in
            self?.startRoamStep()
        }
        scheduledWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func runAfter(_ delay: TimeInterval, action: @escaping () -> Void) {
        cancelScheduledWork()
        let workItem = DispatchWorkItem(block: action)
        scheduledWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelScheduledWork() {
        scheduledWorkItem?.cancel()
        scheduledWorkItem = nil
    }

    private func freezeCurrentPanelMovement() {
        movementID += 1
        let frame = panel.frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            panel.setFrame(frame, display: true)
        }
    }

    private func updateFacing(from origin: CGPoint, to target: CGPoint) {
        let deltaX = target.x - origin.x
        guard abs(deltaX) > 2 else {
            return
        }

        isFacingLeft = deltaX < 0
    }

    private func duration(
        to target: CGPoint,
        speed: CGFloat,
        minimum: TimeInterval,
        maximum: TimeInterval
    ) -> TimeInterval {
        let dx = target.x - currentOrigin.x
        let dy = target.y - currentOrigin.y
        let distance = sqrt(dx * dx + dy * dy)
        let rawDuration = TimeInterval(distance / max(speed, 1))
        return min(max(rawDuration, minimum), maximum)
    }

    private var currentOrigin: CGPoint {
        let frame = panel.frame
        return CGPoint(x: frame.minX, y: frame.minY)
    }

    private var visibleFrames: [CGRect] {
        let frames = NSScreen.screens.map { screen -> CGRect in
            let visibleFrame = screen.visibleFrame
            guard !visibleFrame.isEmpty else {
                return screen.frame
            }

            let intersection = visibleFrame.intersection(screen.frame)
            if intersection.isNull || intersection.isEmpty {
                return screen.frame
            }

            return intersection
        }

        return DesktopPetBehaviorEngine.normalized(frames)
    }

    private var roamSpeed: CGFloat {
        DesktopPetBehaviorEngine.roamSpeed(for: eventBus.sessionState)
    }

    private var nextRoamDelay: TimeInterval {
        switch eventBus.sessionState {
        case .idle:
            return Double.random(in: 2.2...5.8)
        case .thinking, .working:
            return Double.random(in: 1.5...3.2)
        case .streaming:
            return Double.random(in: 0.9...2.0)
        case .awaitingInput:
            return Double.random(in: 2.0...3.6)
        case .error:
            return 2.4
        }
    }

    private func restingAnimation(for state: CodexSessionState) -> PetAnimation {
        PetAnimation.from(state: state)
    }

    private func movingAnimation(for state: CodexSessionState) -> PetAnimation {
        DesktopPetBehaviorEngine.movingAnimation(for: state)
    }
}
