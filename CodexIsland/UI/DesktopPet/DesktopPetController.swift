import AppKit
import Combine
import CoreGraphics

@MainActor
final class DesktopPetController: ObservableObject {
    static let shared = DesktopPetController()

    @Published private(set) var phase: DesktopPetPhase = .disabled {
        didSet { syncInteractionRegion() }
    }
    @Published private(set) var action: DesktopPetAction = .idle {
        didSet { syncInteractionRegion() }
    }
    @Published private(set) var animationName: PetAnimation = .idleBreathe
    @Published private(set) var isFacingLeft = false
    @Published private(set) var presentationScale = DesktopPetMetrics.desktopPresentationScale {
        didSet { syncInteractionRegion() }
    }
    @Published private(set) var userScale = AppSettingsStore.shared.desktopPetScale {
        didSet { syncInteractionRegion() }
    }

    var windowSize: CGSize { DesktopPetScale.windowSize(for: userScale) }
    let petSize = DesktopPetMetrics.petSize

    private let settings = AppSettingsStore.shared
    private let eventBus = EventBus.shared
    private let evolutionStore = PetEvolutionStore.shared
    private let positionStore = DesktopPetPositionStore()
    private var panelStorage: DesktopPetPanel?
    private var cancellables = Set<AnyCancellable>()
    private var scheduledWorkItem: DispatchWorkItem?
    private var movementID = 0
    private var isConfigured = false
    private var isContextMenuPresented = false
    private var dragOffsetInWindow = CGPoint.zero
    private var lastDragScreenLocation: CGPoint?
    private var resizeStartScale: CGFloat?
    private var resizeStartVector: CGVector?
    private var resizeFootAnchorInScreen: CGPoint?
    private var resizeInteraction: DesktopPetResizeInteraction?
    private var scrollResizeWorkItem: DispatchWorkItem?

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
                guard let self,
                      !visible,
                      !self.settings.isDesktopPetEnabled else {
                    return
                }

                self.stopImmediately()
            }
            .store(in: &cancellables)

        settings.$isDesktopPetFreeMovementEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                self?.handleFreeMovementChanged(enabled)
            }
            .store(in: &cancellables)

        settings.$language
            .dropFirst()
            .sink { [weak self] _ in
                self?.syncInteractionRegion()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(evolutionStore.$level, evolutionStore.$currentForm)
            .dropFirst()
            .sink { [weak self] _, _ in
                self?.syncInteractionRegion()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(eventBus.$sessionState, eventBus.$activityKind)
            .dropFirst()
            .sink { [weak self] state, activity in
                self?.reactToSessionChange(state: state, activity: activity)
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
        clearResizeState()
        panelStorage?.orderOut(nil)
    }

    func handleClick(clickCount: Int, screenLocation: CGPoint) {
        guard phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning,
              phase != .dragging,
              phase != .resizing else {
            return
        }

        cancelScheduledWork()
        movementID += 1
        phase = .dodging
        action = .dodging
        animationName = .startledHop

        guard settings.isDesktopPetFreeMovementEnabled else {
            let reactionID = movementID
            runAfter(0.36) { [weak self] in
                guard let self,
                      self.movementID == reactionID,
                      self.phase == .dodging else {
                    return
                }

                self.landAndResume()
            }
            return
        }

        let reactionID = movementID
        runAfter(0.18) { [weak self] in
            guard let self, self.movementID == reactionID, self.phase == .dodging else {
                return
            }

            self.startDodge(from: screenLocation, clickCount: clickCount)
        }
    }

    func handleDragBegan(screenLocation: CGPoint) {
        guard phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning,
              phase != .resizing else {
            return
        }

        cancelScheduledWork()
        movementID += 1
        phase = .dragging
        action = .dragging
        animationName = .dragHover
        dragOffsetInWindow = CGPoint(
            x: screenLocation.x - currentOrigin.x,
            y: screenLocation.y - currentOrigin.y
        )
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
        saveCurrentPosition()
        landAndResume()
    }

    func handleResizeBegan(screenLocation: CGPoint) {
        guard phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning,
              phase != .dragging,
              phase != .resizing else {
            return
        }

        cancelScheduledWork()
        freezeCurrentPanelMovement()
        presentationScale = DesktopPetMetrics.desktopPresentationScale
        let layout = interactionLayout
        let footAnchor = CGPoint(
            x: panel.frame.minX + layout.petFootAnchor.x,
            y: panel.frame.minY + layout.petFootAnchor.y
        )
        resizeStartScale = userScale
        resizeFootAnchorInScreen = footAnchor
        resizeStartVector = CGVector(
            dx: screenLocation.x - footAnchor.x,
            dy: screenLocation.y - footAnchor.y
        )
        resizeInteraction = .drag
        phase = .resizing
        action = .pausing
        animationName = restingAnimation(
            for: eventBus.sessionState,
            activity: eventBus.activityKind
        )
    }

    func handleResizeChanged(screenLocation: CGPoint) {
        guard phase == .resizing,
              resizeInteraction == .drag,
              let startScale = resizeStartScale,
              let startVector = resizeStartVector,
              let footAnchor = resizeFootAnchorInScreen else {
            return
        }

        let currentVector = CGVector(
            dx: screenLocation.x - footAnchor.x,
            dy: screenLocation.y - footAnchor.y
        )
        let nextScale = DesktopPetInteractionGeometry.scale(
            startScale: startScale,
            startVector: startVector,
            currentVector: currentVector
        )
        applyScale(nextScale, anchoredAt: footAnchor)
    }

    func handleResizeEnded(screenLocation: CGPoint) {
        guard phase == .resizing,
              resizeInteraction == .drag else {
            return
        }

        handleResizeChanged(screenLocation: screenLocation)
        settings.desktopPetScale = userScale
        saveCurrentPosition()
        clearResizeState()
        phase = .roaming
        resumeRoaming()
    }

    func handleScrollResize(
        deltaY: CGFloat,
        isPrecise: Bool,
        phaseEnded: Bool
    ) {
        if abs(deltaY) <= 0.001 {
            if phaseEnded, resizeInteraction == .scroll {
                finishScrollResize()
            }
            return
        }

        if resizeInteraction == nil {
            guard phase != .disabled,
                  phase != .waitingForCapsuleStill,
                  phase != .returning,
                  phase != .dragging,
                  phase != .resizing else {
                return
            }
            beginScrollResize()
        }

        guard phase == .resizing,
              resizeInteraction == .scroll,
              let footAnchor = resizeFootAnchorInScreen else {
            return
        }

        let nextScale = DesktopPetScrollScaling.scale(
            from: userScale,
            deltaY: deltaY,
            isPrecise: isPrecise
        )
        applyScale(nextScale, anchoredAt: footAnchor)

        if phaseEnded {
            finishScrollResize()
        } else {
            scheduleScrollResizeFinish()
        }
    }

    func contextMenuWillOpen() -> Bool {
        guard settings.isDesktopPetEnabled,
              phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning,
              phase != .dragging,
              phase != .resizing else {
            return false
        }

        isContextMenuPresented = true
        cancelScheduledWork()
        freezeCurrentPanelMovement()
        saveCurrentPosition()
        phase = .roaming
        applyRestingState(eventBus.sessionState, activity: eventBus.activityKind)
        return true
    }

    func contextMenuDidClose() {
        isContextMenuPresented = false
        guard settings.isDesktopPetEnabled,
              phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning else {
            return
        }

        resumeRoaming()
    }

    private var panel: DesktopPetPanel {
        if let panelStorage {
            return panelStorage
        }

        let panel = DesktopPetPanel(controller: self)
        panelStorage = panel
        syncInteractionRegion()
        return panel
    }

    private func enable() {
        if phase == .waitingForCapsuleStill || phase == .returning {
            resumeFromReturnInterruption()
            return
        }

        cancelScheduledWork()
        movementID += 1

        let anchor = NotchIslandPanel.shared.desktopPetAnchorPoint()
        if !settings.isDesktopPetFreeMovementEnabled {
            showStationaryPet(near: anchor)
            return
        }
        let startOrigin = DesktopPetBehaviorEngine.origin(
            centeredOn: anchor,
            windowSize: windowSize
        )
        let state = eventBus.sessionState
        let activity = eventBus.activityKind

        phase = .launching
        action = .strolling
        animationName = movingAnimation(for: state, activity: activity)
        presentationScale = DesktopPetScale.capsulePresentationScale(for: userScale)
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
                animation: self.movingAnimation(for: state, activity: activity)
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
        clearResizeState()

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
        let activity = eventBus.activityKind
        phase = .roaming
        action = .pausing
        animationName = restingAnimation(for: state, activity: activity)
        presentationScale = DesktopPetMetrics.desktopPresentationScale

        guard settings.isDesktopPetFreeMovementEnabled else {
            scheduleStationaryMicroAction()
            return
        }

        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state, activity: activity) {
            applyStationaryState(state, activity: activity)
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

        presentationScale = DesktopPetScale.capsulePresentationScale(for: userScale)
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
        guard settings.isDesktopPetFreeMovementEnabled else {
            landAndResume()
            return
        }

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

        guard !isContextMenuPresented else {
            return
        }

        guard settings.isDesktopPetFreeMovementEnabled else {
            playRestingMicroAction()
            return
        }

        let state = eventBus.sessionState
        let activity = eventBus.activityKind
        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state, activity: activity) {
            applyStationaryState(state, activity: activity)
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
            animation: movingAnimation(for: state, activity: activity)
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
              phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning else {
            return
        }

        phase = .roaming
        action = .pausing
        applyRestingState(eventBus.sessionState, activity: eventBus.activityKind)
        guard !isContextMenuPresented else {
            return
        }

        guard settings.isDesktopPetFreeMovementEnabled else {
            scheduleStationaryMicroAction()
            return
        }

        if !DesktopPetBehaviorEngine.shouldPauseRoaming(
            for: eventBus.sessionState,
            activity: eventBus.activityKind
        ) {
            scheduleNextRoam(delay: nextRoamDelay)
        }
    }

    private func reactToSessionChange(
        state: CodexSessionState,
        activity: CodexActivityKind
    ) {
        guard settings.isDesktopPetEnabled,
              phase == .roaming else {
            return
        }

        cancelScheduledWork()
        if !settings.isDesktopPetFreeMovementEnabled {
            applyRestingState(state, activity: activity)
            scheduleStationaryMicroAction()
            return
        }

        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state, activity: activity) {
            applyStationaryState(
                state,
                activity: activity,
                shouldFreezeCurrentMovement: action == .strolling
            )
            return
        }

        if action == .strolling {
            animationName = movingAnimation(for: state, activity: activity)
        } else {
            action = .pausing
            animationName = restingAnimation(for: state, activity: activity)
            scheduleNextRoam(delay: nextRoamDelay)
        }
    }

    private func playRestingMicroAction(delayOverride: TimeInterval? = nil) {
        guard settings.isDesktopPetEnabled,
              phase == .roaming else {
            return
        }

        let state = eventBus.sessionState
        let activity = eventBus.activityKind
        if state == .notLoaded || state == .idle {
            action = .pausing
            animationName = .idleWait
            scheduleNextRoam(
                delay: delayOverride ?? DesktopPetRoamingPolicy.idleRestDelay()
            )
            return
        }
        let selectedAction = microAction(for: state, activity: activity)
        action = selectedAction
        animationName = animation(for: selectedAction, state: state, activity: activity)
        scheduleNextRoam(
            delay: delayOverride ?? delay(for: selectedAction, state: state, activity: activity)
        )
    }

    private func applyRestingState(
        _ state: CodexSessionState,
        activity: CodexActivityKind
    ) {
        if DesktopPetBehaviorEngine.shouldPauseRoaming(for: state, activity: activity)
            && state == .waitingForInput {
            action = .hopping
        } else {
            action = .pausing
        }
        animationName = restingAnimation(for: state, activity: activity)
    }

    private func applyStationaryState(
        _ state: CodexSessionState,
        activity: CodexActivityKind,
        shouldFreezeCurrentMovement: Bool = false
    ) {
        cancelScheduledWork()
        if shouldFreezeCurrentMovement {
            freezeCurrentPanelMovement()
        }
        applyRestingState(state, activity: activity)
    }

    private func microAction(
        for state: CodexSessionState,
        activity: CodexActivityKind
    ) -> DesktopPetAction {
        switch state {
        case .notLoaded, .idle:
            return [.pausing, .lookingAround, .hopping].randomElement() ?? .pausing
        case .running:
            switch activity {
            case .reasoning:
                return [.pausing, .lookingAround].randomElement() ?? .lookingAround
            case .fileChange, .agentMessage:
                return [.pausing, .hopping].randomElement() ?? .pausing
            case .none, .commandExecution, .webSearch:
                return [.pausing, .lookingAround].randomElement() ?? .lookingAround
            }
        case .waitingForInput:
            return .hopping
        case .readyForReview, .error:
            return .pausing
        }
    }

    private func animation(
        for action: DesktopPetAction,
        state: CodexSessionState,
        activity: CodexActivityKind
    ) -> PetAnimation {
        switch action {
        case .hopping:
            return state == .waitingForInput ? restingAnimation(for: state, activity: activity) : .happyBounce
        case .lookingAround:
            return DesktopPetBehaviorEngine.shouldPauseRoaming(for: state, activity: activity)
                ? restingAnimation(for: state, activity: activity)
                : .idleStretch
        case .pausing:
            return restingAnimation(for: state, activity: activity)
        case .landing:
            return .landBounce
        case .strolling, .dodging, .returning:
            return movingAnimation(for: state, activity: activity)
        case .dragging:
            return .dragHover
        case .idle:
            return restingAnimation(for: state, activity: activity)
        }
    }

    private func delay(
        for action: DesktopPetAction,
        state: CodexSessionState,
        activity: CodexActivityKind
    ) -> TimeInterval {
        switch action {
        case .hopping:
            return state == .running && (activity == .fileChange || activity == .agentMessage) ? 1.2 : 1.8
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

        let wasDirectInteraction = phase == .dragging || phase == .resizing
        if !wasDirectInteraction {
            cancelScheduledWork()
            freezeCurrentPanelMovement()
        }
        let clamped = DesktopPetBehaviorEngine.clampedOrigin(
            currentOrigin,
            windowSize: windowSize,
            in: visibleFrames
        )
        panel.setFrame(NSRect(origin: clamped, size: windowSize), display: true)
        if phase == .resizing {
            let layout = interactionLayout
            let footAnchor = CGPoint(
                x: clamped.x + layout.petFootAnchor.x,
                y: clamped.y + layout.petFootAnchor.y
            )
            let mouseLocation = NSEvent.mouseLocation
            resizeFootAnchorInScreen = footAnchor
            if resizeInteraction == .drag {
                resizeStartScale = userScale
                resizeStartVector = CGVector(
                    dx: mouseLocation.x - footAnchor.x,
                    dy: mouseLocation.y - footAnchor.y
                )
            }
        }
        saveCurrentPosition()
        if !wasDirectInteraction {
            resumeRoaming()
        }
    }

    private func movePanel(
        to target: CGPoint,
        duration: TimeInterval,
        phase nextPhase: DesktopPetPhase,
        action nextAction: DesktopPetAction,
        animation: PetAnimation,
        completion: (() -> Void)? = nil
    ) {
        guard nextPhase == .returning || settings.isDesktopPetFreeMovementEnabled else {
            resumeRoaming()
            return
        }

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

    private func handleFreeMovementChanged(_ enabled: Bool) {
        guard settings.isDesktopPetEnabled,
              phase != .disabled,
              phase != .waitingForCapsuleStill,
              phase != .returning,
              phase != .resizing else {
            return
        }

        cancelScheduledWork()
        freezeCurrentPanelMovement()
        presentationScale = DesktopPetMetrics.desktopPresentationScale
        if !enabled {
            let clamped = DesktopPetBehaviorEngine.clampedOrigin(
                currentOrigin,
                windowSize: windowSize,
                in: visibleFrames
            )
            panel.setFrame(NSRect(origin: clamped, size: windowSize), display: true)
            saveCurrentPosition()
        }

        phase = .roaming
        applyRestingState(eventBus.sessionState, activity: eventBus.activityKind)
        guard !isContextMenuPresented else {
            return
        }

        if enabled {
            resumeRoaming()
        } else {
            scheduleStationaryMicroAction()
        }
    }

    private func showStationaryPet(near anchor: CGPoint) {
        let origin = positionStore.restoredOrigin(
            windowSize: windowSize,
            displays: displayGeometries
        ) ?? DesktopPetBehaviorEngine.attentionTarget(
            near: anchor,
            windowSize: windowSize,
            in: visibleFrames
        )
        let clamped = DesktopPetBehaviorEngine.clampedOrigin(
            origin,
            windowSize: windowSize,
            in: visibleFrames
        )

        panel.setFrame(NSRect(origin: clamped, size: windowSize), display: true)
        panel.orderFrontRegardless()
        presentationScale = DesktopPetMetrics.desktopPresentationScale
        phase = .roaming
        applyRestingState(eventBus.sessionState, activity: eventBus.activityKind)
        saveCurrentPosition()
        scheduleStationaryMicroAction()
    }

    private func scheduleStationaryMicroAction() {
        guard settings.isDesktopPetEnabled,
              !settings.isDesktopPetFreeMovementEnabled,
              !isContextMenuPresented,
              phase == .roaming else {
            return
        }

        scheduleNextRoam(delay: nextRoamDelay)
    }

    private func saveCurrentPosition() {
        guard let panelStorage,
              let display = displayGeometry(containing: panelStorage.frame) else {
            return
        }

        positionStore.save(windowFrame: panelStorage.frame, on: display)
    }

    private var interactionLayout: DesktopPetInteractionLayout {
        DesktopPetInteractionGeometry.layout(
            userScale: userScale,
            presentationScale: presentationScale,
            level: evolutionStore.level,
            normalizedOpaqueBounds: PetAtlasRepository.shared.normalizedOpaqueBounds(
                for: evolutionStore.currentForm
            )
        )
    }

    private func syncInteractionRegion() {
        guard let panelStorage else {
            return
        }
        let canResize = phase == .roaming || phase == .dropped || phase == .resizing
        panelStorage.updateInteractionRegion(
            interactionLayout,
            showsResizeHandle: canResize && presentationScale == 1,
            resizeToolTip: settings.language == .chinese
                ? "拖拽或滚轮调整宠物大小"
                : "Drag or scroll to resize pet"
        )
    }

    private func clearResizeState() {
        scrollResizeWorkItem?.cancel()
        scrollResizeWorkItem = nil
        resizeStartScale = nil
        resizeStartVector = nil
        resizeFootAnchorInScreen = nil
        resizeInteraction = nil
    }

    private func beginScrollResize() {
        cancelScheduledWork()
        freezeCurrentPanelMovement()
        presentationScale = DesktopPetMetrics.desktopPresentationScale
        let layout = interactionLayout
        resizeFootAnchorInScreen = CGPoint(
            x: panel.frame.minX + layout.petFootAnchor.x,
            y: panel.frame.minY + layout.petFootAnchor.y
        )
        resizeStartScale = nil
        resizeStartVector = nil
        resizeInteraction = .scroll
        phase = .resizing
        action = .pausing
        animationName = restingAnimation(
            for: eventBus.sessionState,
            activity: eventBus.activityKind
        )
    }

    private func applyScale(_ scale: CGFloat, anchoredAt footAnchor: CGPoint) {
        userScale = DesktopPetScale.clamped(scale)
        let layout = interactionLayout
        let proposedOrigin = CGPoint(
            x: footAnchor.x - layout.petFootAnchor.x,
            y: footAnchor.y - layout.petFootAnchor.y
        )
        let clampedOrigin = DesktopPetBehaviorEngine.clampedOrigin(
            proposedOrigin,
            windowSize: windowSize,
            in: visibleFrames
        )
        panel.setFrame(
            CGRect(origin: clampedOrigin, size: windowSize),
            display: true
        )
        syncInteractionRegion()
    }

    private func scheduleScrollResizeFinish() {
        scrollResizeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishScrollResize()
        }
        scrollResizeWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopPetScrollScaling.finishDelay,
            execute: workItem
        )
    }

    private func finishScrollResize() {
        guard phase == .resizing,
              resizeInteraction == .scroll else {
            return
        }
        settings.desktopPetScale = userScale
        saveCurrentPosition()
        clearResizeState()
        phase = .roaming
        resumeRoaming()
    }

    private func displayGeometry(containing frame: CGRect) -> DesktopPetDisplayGeometry? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displayGeometries.first { $0.visibleFrame.contains(center) }
            ?? displayGeometries.max {
                intersectionArea($0.visibleFrame, frame)
                    < intersectionArea($1.visibleFrame, frame)
            }
            ?? displayGeometries.first
    }

    private func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }
        return intersection.width * intersection.height
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

    private var displayGeometries: [DesktopPetDisplayGeometry] {
        NSScreen.screens.map {
            DesktopPetDisplayGeometry(
                identifier: $0.codexIslandIdentifier,
                visibleFrame: normalizedVisibleFrame(for: $0)
            )
        }
    }

    private func normalizedVisibleFrame(for screen: NSScreen) -> CGRect {
        let visibleFrame = screen.visibleFrame
        guard !visibleFrame.isEmpty else {
            return screen.frame
        }

        let intersection = visibleFrame.intersection(screen.frame)
        return intersection.isNull || intersection.isEmpty ? screen.frame : intersection
    }

    private var roamSpeed: CGFloat {
        DesktopPetBehaviorEngine.roamSpeed(
            for: eventBus.sessionState,
            activity: eventBus.activityKind
        )
    }

    private var nextRoamDelay: TimeInterval {
        switch eventBus.sessionState {
        case .notLoaded, .idle:
            return DesktopPetRoamingPolicy.idleRestDelay()
        case .running:
            switch eventBus.activityKind {
            case .reasoning:
                return Double.random(in: 1.5...3.2)
            case .fileChange, .agentMessage:
                return Double.random(in: 0.9...2.0)
            case .none, .commandExecution:
                return Double.random(in: 1.5...3.2)
            case .webSearch:
                return Double.random(in: 1.4...2.8)
            }
        case .waitingForInput:
            return Double.random(in: 2.0...3.6)
        case .readyForReview:
            return 2.2
        case .error:
            return 2.4
        }
    }

    private func restingAnimation(
        for state: CodexSessionState,
        activity: CodexActivityKind
    ) -> PetAnimation {
        if state == .notLoaded || state == .idle {
            return .idleWait
        }
        return PetAnimation.from(state: state, activityKind: activity)
    }

    private func movingAnimation(
        for state: CodexSessionState,
        activity: CodexActivityKind
    ) -> PetAnimation {
        DesktopPetBehaviorEngine.movingAnimation(for: state, activity: activity)
    }
}

private enum DesktopPetResizeInteraction {
    case drag
    case scroll
}
