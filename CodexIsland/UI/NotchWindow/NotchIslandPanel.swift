import AppKit
import Combine
import SwiftUI

final class NotchIslandPanel: NSPanel {
    static let shared = NotchIslandPanel()

    private let contentModel = NotchIslandContentModel()
    private let positionStore = IslandPositionStore()
    private let settings = AppSettingsStore.shared
    private var transitionState = IslandWindowTransitionState(restingShape: .pill)
    private var isPressingForDrag = false
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var dragResistanceScreen: NSScreen?
    private var suppressHoverExpansionUntilMouseExit = false
    private var outsideClickGlobalMonitor: Any?
    private var outsideClickLocalMonitor: Any?
    private var anchorState = IslandWindowAnchorState()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: IslandShape.pillSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        transitionState.reset(restingShape: .pill)

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let rootView = NotchIslandView(model: contentModel)
        let hostingView = NotchIslandHostingView(rootView: rootView)
        IslandHostingSizingPolicy.configure(hostingView)
        hostingView.onHoverChanged = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        hostingView.onDragHandlePressed = { [weak self] event in
            self?.trackHandleDrag(with: event)
        }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView

        observeSettings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopOutsideClickMonitoring()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard settings.isCapsuleVisible else {
            orderOut(nil)
            return
        }

        resetInteractionStateForVisibility()
        anchorState.invalidate()
        relayout(animated: false, resolvesAnchor: true)
        orderFrontRegardless()
    }

    func presentSettings() {
        if !settings.isCapsuleVisible {
            settings.isCapsuleVisible = true
        }
        if !isVisible {
            show()
        }

        contentModel.expandedMode = .settings
        if transitionState.isExpansionActive,
           transitionState.currentShape == .expanded {
            contentModel.isExpandedContainer = true
            contentModel.isExpanded = true
            orderFrontRegardless()
            return
        }

        _ = transitionState.activateExpansion(for: settings.capsuleExpansionTrigger)
        contentModel.isExpanded = false
        contentModel.isExpandedContainer = true
        if settings.capsuleExpansionTrigger == .click {
            startOutsideClickMonitoring()
        }
        transition(to: .expanded)
        orderFrontRegardless()
    }

    func hide() {
        isDragging = false
        isPressingForDrag = false
        contentModel.isExpanded = false
        contentModel.isExpandedContainer = false
        contentModel.expandedMode = .dashboard
        transitionState.reset(restingShape: transitionState.restingShape)
        stopOutsideClickMonitoring()
        orderOut(nil)
    }

    func transition(
        to shape: IslandShape,
        animated: Bool = true
    ) {
        transitionState.setCurrentShape(shape)
        relayout(animated: animated)
    }

    func resetPosition() {
        positionStore.resetAll()
        anchorState.invalidate()
        relayout(animated: true, resolvesAnchor: true)
    }

    func desktopPetAnchorPoint() -> NSPoint {
        guard isVisible, frame.width > 0, frame.height > 0 else {
            return fallbackDesktopPetAnchorPoint()
        }

        return NSPoint(x: frame.midX, y: frame.minY + 2)
    }

    private func observeSettings() {
        settings.$capsuleStyle
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.applyCapsuleStyleChange()
                }
            }
            .store(in: &cancellables)

        settings.$isDesktopPetEnabled
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.relayout(animated: true)
                }
            }
            .store(in: &cancellables)

        settings.$isCapsuleVisible
            .dropFirst()
            .sink { [weak self] visible in
                guard let self else {
                    return
                }

                if visible {
                    self.show()
                } else {
                    self.hide()
                }
            }
            .store(in: &cancellables)

        settings.$capsuleExpansionTrigger
            .dropFirst()
            .sink { [weak self] trigger in
                self?.handleExpansionTriggerChanged(trigger)
            }
            .store(in: &cancellables)

    }

    private func setHovered(_ hovered: Bool) {
        guard settings.capsuleExpansionTrigger == .hover else {
            return
        }

        guard !isDragging, !isPressingForDrag else {
            return
        }

        if !hovered {
            suppressHoverExpansionUntilMouseExit = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.syncHoverStateWithMouseLocation()
            }
            return
        }

        guard !suppressHoverExpansionUntilMouseExit else {
            return
        }

        guard !transitionState.isExpansionActive else {
            return
        }

        expandForInteraction(trigger: .hover)
    }

    private func syncHoverStateWithMouseLocation() {
        guard isVisible,
              settings.isCapsuleVisible,
              settings.capsuleExpansionTrigger == .hover else {
            return
        }

        guard !isDragging, !isPressingForDrag else {
            return
        }

        let isMouseInside = frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)

        if suppressHoverExpansionUntilMouseExit {
            guard !isMouseInside else {
                return
            }
            suppressHoverExpansionUntilMouseExit = false
        }

        if isMouseInside {
            if !transitionState.isExpansionActive {
                expandForInteraction(trigger: .hover)
            } else {
                transition(to: .expanded)
            }
            return
        }

        guard transitionState.isExpansionActive else {
            return
        }

        collapseFromInteraction()
    }

    private func expandForInteraction(trigger: CapsuleExpansionTrigger) {
        guard transitionState.activateExpansion(for: trigger) else {
            return
        }

        contentModel.isExpanded = false
        contentModel.isExpandedContainer = true
        if trigger == .click {
            startOutsideClickMonitoring()
        }

        transition(to: .expanded)
    }

    private func collapseFromInteraction() {
        transitionState.deactivateExpansion()
        contentModel.isExpanded = false
        contentModel.expandedMode = .dashboard
        stopOutsideClickMonitoring()

        transition(to: transitionState.restingShape)
    }

    private func applyCapsuleStyleChange() {
        guard isVisible, settings.isCapsuleVisible else {
            return
        }

        if transitionState.isExpansionActive || transitionState.currentShape == .expanded {
            suppressHoverExpansionUntilMouseExit = settings.capsuleExpansionTrigger == .hover
            collapseFromInteraction()
            return
        }

        transition(to: transitionState.restingShape)
    }

    @objc private func screenParametersChanged() {
        let screens = NSScreen.screens
        guard let anchor = anchorState.anchor,
              let anchoredScreen = screens.first(where: {
                  $0.codexIslandIdentifier == anchor.screenIdentifier
              }) else {
            anchorState.invalidate()
            relayout(animated: false, resolvesAnchor: true)
            return
        }

        let notchFrame = calculateNotchFrame(for: anchoredScreen)
        let currentSize = calculateWindowFrame(
            shape: transitionState.currentShape,
            notchFrame: notchFrame,
            screen: anchoredScreen
        ).size
        anchorState.preserveForScreenChange(
            usableFrame: usableFrame(for: anchoredScreen),
            currentSize: currentSize
        )
        relayout(animated: false)
    }

    private func setPressingForDrag(_ pressing: Bool) {
        isPressingForDrag = pressing

        if !pressing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.syncHoverStateWithMouseLocation()
            }
        }
    }

    private func trackHandleDrag(with startEvent: NSEvent) {
        guard let eventWindow = startEvent.window, eventWindow == self else {
            return
        }

        let startLocation = screenLocation(for: startEvent)
        var movedBeyondClickThreshold = false
        beginDrag(at: startLocation)

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        while isDragging {
            guard let nextEvent = eventWindow.nextEvent(
                matching: eventMask,
                until: .distantFuture,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                let location = screenLocation(for: nextEvent)
                if IslandPressGesture.isDrag(from: startLocation, to: location) {
                    movedBeyondClickThreshold = true
                }
                if movedBeyondClickThreshold {
                    drag(to: location)
                }
            case .leftMouseUp:
                let location = screenLocation(for: nextEvent)
                let isClick = !movedBeyondClickThreshold
                    && IslandPressGesture.isClick(from: startLocation, to: location)
                endDrag(savePosition: movedBeyondClickThreshold)
                if isClick {
                    handleCapsuleClick()
                }
                return
            default:
                break
            }
        }
    }

    private func beginDrag(at location: NSPoint) {
        transitionState.invalidateTransitions()
        isDragging = true
        dragStartMouseLocation = location
        dragStartFrame = frame
        dragResistanceScreen = screen(containing: frame)
            ?? screen(withLargestIntersection: frame)
            ?? targetScreen()
        setPressingForDrag(true)
    }

    private func drag(to location: NSPoint) {
        guard isDragging else {
            return
        }

        let deltaX = location.x - dragStartMouseLocation.x
        let deltaY = location.y - dragStartMouseLocation.y
        let proposedFrame = dragStartFrame.offsetBy(dx: deltaX, dy: deltaY)

        let resistedFrame = frameAfterApplyingDisplayBoundaryResistance(to: proposedFrame)
        setFrame(resistedFrame, display: true)
    }

    private func endDrag(savePosition: Bool = true) {
        guard isDragging else {
            return
        }

        isDragging = false
        dragResistanceScreen = nil
        if savePosition {
            saveCurrentPosition()
        }
        setPressingForDrag(false)
        transition(
            to: transitionState.isExpansionActive
                ? .expanded
                : transitionState.restingShape
        )
    }

    private func handleCapsuleClick() {
        guard settings.capsuleExpansionTrigger == .click,
              transitionState.currentShape != .expanded else {
            return
        }

        expandForInteraction(trigger: .click)
    }

    private func handleExpansionTriggerChanged(_ trigger: CapsuleExpansionTrigger) {
        stopOutsideClickMonitoring()

        switch trigger {
        case .hover:
            syncHoverStateWithMouseLocation()
        case .click:
            if transitionState.currentShape == .expanded {
                collapseFromInteraction()
            }
        }
    }

    private func startOutsideClickMonitoring() {
        guard outsideClickGlobalMonitor == nil,
              outsideClickLocalMonitor == nil else {
            return
        }

        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            DispatchQueue.main.async {
                self?.collapseForOutsideClick(at: NSEvent.mouseLocation)
            }
        }
        outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            self?.collapseForOutsideClick(event: event)
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let outsideClickGlobalMonitor {
            NSEvent.removeMonitor(outsideClickGlobalMonitor)
            self.outsideClickGlobalMonitor = nil
        }
        if let outsideClickLocalMonitor {
            NSEvent.removeMonitor(outsideClickLocalMonitor)
            self.outsideClickLocalMonitor = nil
        }
    }

    private func collapseForOutsideClick(event: NSEvent) {
        guard event.window != self else {
            return
        }

        collapseForOutsideClick(at: NSEvent.mouseLocation)
    }

    private func collapseForOutsideClick(at point: NSPoint) {
        guard settings.capsuleExpansionTrigger == .click,
              transitionState.currentShape == .expanded,
              !frame.contains(point) else {
            return
        }

        collapseFromInteraction()
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window, eventWindow == self else {
            return NSEvent.mouseLocation
        }

        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }

    private func saveCurrentPosition() {
        guard let screen = screen(containing: NSPoint(x: frame.midX, y: frame.midY))
            ?? screen(withLargestIntersection: frame)
            ?? screen(nearestTo: NSPoint(x: frame.midX, y: frame.midY))
            ?? targetScreen() else {
            return
        }

        let anchor = anchorState.updateAfterDrag(
            screenIdentifier: screen.codexIslandIdentifier,
            frame: frame
        )

        let notchFrame = calculateNotchFrame(for: screen)
        let restingSize = calculateWindowFrame(
            shape: transitionState.restingShape,
            notchFrame: notchFrame,
            screen: screen
        ).size
        let restingFrame = IslandWindowGeometry.frame(
            size: restingSize,
            anchoredTo: anchor
        )
        positionStore.save(
            frame: restingFrame,
            on: screen,
            usableFrame: usableFrame(for: screen)
        )
    }

    private func resetInteractionStateForVisibility() {
        transitionState.reset(restingShape: .pill)
        isPressingForDrag = false
        isDragging = false
        suppressHoverExpansionUntilMouseExit = false
        contentModel.isExpanded = false
        contentModel.isExpandedContainer = false
        contentModel.expandedMode = .dashboard
        stopOutsideClickMonitoring()
    }

    private func relayout(
        animated: Bool,
        resolvesAnchor: Bool = false
    ) {
        guard settings.isCapsuleVisible else {
            transitionState.invalidateTransitions()
            orderOut(nil)
            return
        }

        guard let screen = targetScreen() else {
            transitionState.invalidateTransitions()
            return
        }

        let notchFrame = calculateNotchFrame(for: screen)
        let proposedWindowFrame = calculateWindowFrame(
            shape: transitionState.currentShape,
            notchFrame: notchFrame,
            screen: screen
        )
        let screenIdentifier = screen.codexIslandIdentifier
        if anchorState.needsResolution(
            for: screenIdentifier,
            forced: resolvesAnchor
        ) {
            let restingWindowFrame = calculateWindowFrame(
                shape: transitionState.restingShape,
                notchFrame: notchFrame,
                screen: screen
            )
            anchorState.resolve(
                screenIdentifier: screenIdentifier,
                restingFrame: restingWindowFrame
            )
        }

        guard let windowAnchor = anchorState.anchor else {
            transitionState.invalidateTransitions()
            return
        }

        let transition = transitionState.beginTransition(
            size: proposedWindowFrame.size,
            anchoredTo: windowAnchor
        )
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = transition.targetShape == .expanded ? 0.30 : 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(transition.targetFrame, display: true)
            } completionHandler: { [weak self] in
                self?.reconcileContentStateAfterLayout(
                    transition: transition
                )
            }
        } else {
            setFrame(transition.targetFrame, display: true)
            reconcileContentStateAfterLayout(transition: transition)
        }
    }

    private func reconcileContentStateAfterLayout(transition: IslandWindowTransition) {
        guard let presentationState = transitionState.settledPresentationState(
            for: transition.id,
            isDragging: isDragging,
            isPressingForDrag: isPressingForDrag
        ) else {
            return
        }

        switch presentationState {
        case .expanded:
            contentModel.isExpandedContainer = true
            contentModel.isExpanded = true
        case .collapsed:
            contentModel.isExpanded = false
            contentModel.isExpandedContainer = false
        }

        DispatchQueue.main.async { [weak self] in
            self?.correctLatestTransitionFrameIfNeeded(transition)
        }
    }

    private func correctLatestTransitionFrameIfNeeded(_ transition: IslandWindowTransition) {
        guard transitionState.isCurrentTransition(transition.id),
              !isDragging,
              !isPressingForDrag,
              IslandWindowGeometry.needsCorrection(
                  actual: frame,
                  target: transition.targetFrame
              ) else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            setFrame(transition.targetFrame, display: true)
        }
    }

    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let savedScreen = positionStore.preferredScreen(in: screens)
        let primary = primaryScreen(from: screens)
        guard let selectedIdentifier = IslandScreenSelection.preferredIdentifier(
            availableIdentifiers: screens.map(\.codexIslandIdentifier),
            anchorIdentifier: anchorState.anchor?.screenIdentifier,
            savedIdentifier: savedScreen?.codexIslandIdentifier,
            primaryIdentifier: primary?.codexIslandIdentifier
        ) else {
            return nil
        }

        return screens.first {
            $0.codexIslandIdentifier == selectedIdentifier
        }
    }

    private func fallbackDesktopPetAnchorPoint() -> NSPoint {
        guard let screen = targetScreen() else {
            return NSEvent.mouseLocation
        }

        let notchFrame = calculateNotchFrame(for: screen)
        return NSPoint(
            x: notchFrame.midX,
            y: usableFrame(for: screen).maxY - IslandShape.topGap - IslandShape.fallbackCompactSize.height
        )
    }

    private func primaryScreen(from screens: [NSScreen]) -> NSScreen? {
        screens.first { screen in
            screen.frame.origin == .zero
        } ?? NSScreen.main ?? screens.first
    }

    private func calculateNotchFrame(for screen: NSScreen) -> NSRect {
        guard screen.hasAuxiliaryTopAreas,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return fallbackNotchFrame(for: screen)
        }

        let notchWidth = max(
            screen.frame.width - leftArea.width - rightArea.width,
            IslandShape.fallbackCompactSize.width
        )
        let notchHeight = resolvedTopBandHeight(from: leftArea, on: screen)
        let notchX = screen.frame.minX + leftArea.width
        let notchY = screen.frame.maxY - notchHeight

        return NSRect(
            x: notchX,
            y: notchY,
            width: notchWidth,
            height: notchHeight
        )
    }

    private func fallbackNotchFrame(for screen: NSScreen) -> NSRect {
        let usableFrame = usableFrame(for: screen)
        return NSRect(
            x: usableFrame.midX - IslandShape.fallbackCompactSize.width / 2,
            y: usableFrame.maxY - IslandShape.fallbackCompactSize.height,
            width: IslandShape.fallbackCompactSize.width,
            height: IslandShape.fallbackCompactSize.height
        )
    }

    private func resolvedTopBandHeight(from leftArea: NSRect, on screen: NSScreen) -> CGFloat {
        let globalCandidate = screen.frame.maxY - leftArea.minY
        if (20...80).contains(globalCandidate) {
            return globalCandidate
        }

        let localCandidate = screen.frame.height - leftArea.minY
        if (20...80).contains(localCandidate) {
            return localCandidate
        }

        return IslandShape.fallbackCompactSize.height
    }

    private func calculateWindowFrame(
        shape: IslandShape,
        notchFrame: NSRect,
        screen: NSScreen
    ) -> NSRect {
        let usableFrame = usableFrame(for: screen)
        var size = shape.size(
            fitting: notchFrame,
            capsuleStyle: settings.capsuleStyle,
            desktopPetEnabled: settings.isDesktopPetEnabled
        )
        size.width = min(size.width, usableFrame.width)
        size.height = min(size.height, usableFrame.height - IslandShape.topGap)

        let x = clampedX(
            centeredAt: notchFrame.midX,
            width: size.width,
            screen: screen
        )

        if let savedOrigin = positionStore.origin(for: size, on: screen, usableFrame: usableFrame) {
            return NSRect(origin: savedOrigin, size: size)
        }

        switch shape {
        case .compact, .pill:
            return NSRect(
                x: x,
                y: usableFrame.maxY - IslandShape.topGap - size.height,
                width: size.width,
                height: size.height
            )
        case .expanded:
            return NSRect(
                x: x,
                y: usableFrame.maxY - IslandShape.topGap - size.height,
                width: size.width,
                height: size.height
            )
        }
    }

    private func clampedX(centeredAt centerX: CGFloat, width: CGFloat, screen: NSScreen) -> CGFloat {
        let usableFrame = usableFrame(for: screen)
        let proposedX = centerX - width / 2
        let minX = usableFrame.minX
        let maxX = usableFrame.maxX - width
        return min(max(proposedX, minX), maxX)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return screen(containing: center)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }

    private func screen(withLargestIntersection rect: NSRect) -> NSScreen? {
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
        guard let screen,
              screen.frame.intersection(rect).area > 0 else {
            return nil
        }

        return screen
    }

    private func screen(nearestTo point: NSPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            lhs.frame.squaredDistance(to: point) < rhs.frame.squaredDistance(to: point)
        }
    }

    private func frameAfterApplyingDisplayBoundaryResistance(to proposedFrame: NSRect) -> NSRect {
        guard NSScreen.screens.count > 1,
              let resistanceScreen = dragResistanceScreen else {
            return proposedFrame
        }

        let usableFrame = usableFrame(for: resistanceScreen)
        guard let crossing = strongestBoundaryCrossing(
            proposedFrame,
            beyond: usableFrame,
            from: resistanceScreen
        ) else {
            return proposedFrame
        }

        if crossing.penetration >= DragResistance.threshold {
            dragResistanceScreen = nil
            return proposedFrame
        }

        return frameSnapped(
            proposedFrame,
            to: crossing.edge,
            of: usableFrame
        )
    }

    private func strongestBoundaryCrossing(
        _ frame: NSRect,
        beyond usableFrame: NSRect,
        from screen: NSScreen
    ) -> (edge: DragResistanceEdge, penetration: CGFloat)? {
        let crossings: [(DragResistanceEdge, CGFloat)] = [
            (.minX, usableFrame.minX - frame.minX),
            (.maxX, frame.maxX - usableFrame.maxX),
            (.minY, usableFrame.minY - frame.minY),
            (.maxY, frame.maxY - usableFrame.maxY)
        ]

        return crossings
            .filter { edge, penetration in
                penetration > 0
                    && self.screen(across: edge, from: screen, near: frame) != nil
            }
            .max { lhs, rhs in
                lhs.1 < rhs.1
            }
    }

    private func frameSnapped(
        _ frame: NSRect,
        to edge: DragResistanceEdge,
        of usableFrame: NSRect
    ) -> NSRect {
        var snappedFrame = frame

        switch edge {
        case .minX:
            snappedFrame.origin.x = usableFrame.minX
        case .maxX:
            snappedFrame.origin.x = usableFrame.maxX - frame.width
        case .minY:
            snappedFrame.origin.y = usableFrame.minY
        case .maxY:
            snappedFrame.origin.y = usableFrame.maxY - frame.height
        }

        return snappedFrame
    }

    private func screen(
        across edge: DragResistanceEdge,
        from screen: NSScreen,
        near frame: NSRect
    ) -> NSScreen? {
        let probeOffset: CGFloat = 2
        let point: NSPoint

        switch edge {
        case .minX:
            point = NSPoint(x: screen.frame.minX - probeOffset, y: frame.midY)
        case .maxX:
            point = NSPoint(x: screen.frame.maxX + probeOffset, y: frame.midY)
        case .minY:
            point = NSPoint(x: frame.midX, y: screen.frame.minY - probeOffset)
        case .maxY:
            point = NSPoint(x: frame.midX, y: screen.frame.maxY + probeOffset)
        }

        return NSScreen.screens.first { candidate in
            candidate.codexIslandIdentifier != screen.codexIslandIdentifier
                && candidate.frame.insetBy(dx: -2, dy: -2).contains(point)
        }
    }

    private func usableFrame(for screen: NSScreen) -> NSRect {
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
}

struct IslandWindowAnchor: Equatable {
    let screenIdentifier: String
    let midX: CGFloat
    let maxY: CGFloat
}

struct IslandWindowAnchorState {
    private(set) var anchor: IslandWindowAnchor?

    func needsResolution(
        for screenIdentifier: String,
        forced: Bool = false
    ) -> Bool {
        forced || anchor?.screenIdentifier != screenIdentifier
    }

    @discardableResult
    mutating func resolve(
        screenIdentifier: String,
        restingFrame: NSRect
    ) -> IslandWindowAnchor {
        let resolvedAnchor = IslandWindowAnchor(
            screenIdentifier: screenIdentifier,
            midX: restingFrame.midX,
            maxY: restingFrame.maxY
        )
        anchor = resolvedAnchor
        return resolvedAnchor
    }

    @discardableResult
    mutating func updateAfterDrag(
        screenIdentifier: String,
        frame: NSRect
    ) -> IslandWindowAnchor {
        resolve(screenIdentifier: screenIdentifier, restingFrame: frame)
    }

    mutating func preserveForScreenChange(
        usableFrame: NSRect,
        currentSize: NSSize
    ) {
        guard let anchor else {
            return
        }

        self.anchor = IslandWindowGeometry.clampedAnchor(
            anchor,
            for: currentSize,
            within: usableFrame
        )
    }

    mutating func invalidate() {
        anchor = nil
    }
}

enum IslandScreenSelection {
    static func preferredIdentifier(
        availableIdentifiers: [String],
        anchorIdentifier: String?,
        savedIdentifier: String?,
        primaryIdentifier: String?
    ) -> String? {
        for candidate in [anchorIdentifier, savedIdentifier, primaryIdentifier] {
            if let candidate,
               availableIdentifiers.contains(candidate) {
                return candidate
            }
        }

        return availableIdentifiers.first
    }
}

enum IslandWindowGeometry {
    static let frameTolerance: CGFloat = 0.5

    static func frame(size: NSSize, anchoredTo anchor: IslandWindowAnchor) -> NSRect {
        NSRect(
            x: anchor.midX - size.width / 2,
            y: anchor.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func clampedAnchor(
        _ anchor: IslandWindowAnchor,
        for size: NSSize,
        within usableFrame: NSRect
    ) -> IslandWindowAnchor {
        let halfWidth = min(size.width, usableFrame.width) / 2
        let minMidX = usableFrame.minX + halfWidth
        let maxMidX = usableFrame.maxX - halfWidth
        let minMaxY = usableFrame.minY + min(size.height, usableFrame.height)

        return IslandWindowAnchor(
            screenIdentifier: anchor.screenIdentifier,
            midX: min(max(anchor.midX, minMidX), maxMidX),
            maxY: min(max(anchor.maxY, minMaxY), usableFrame.maxY)
        )
    }

    static func needsCorrection(
        actual: NSRect,
        target: NSRect,
        tolerance: CGFloat = frameTolerance
    ) -> Bool {
        abs(actual.origin.x - target.origin.x) > tolerance
            || abs(actual.origin.y - target.origin.y) > tolerance
            || abs(actual.size.width - target.size.width) > tolerance
            || abs(actual.size.height - target.size.height) > tolerance
    }
}

struct IslandTransitionTracker {
    private(set) var currentID: UInt64 = 0

    mutating func begin() -> UInt64 {
        currentID &+= 1
        return currentID
    }

    func isCurrent(_ transitionID: UInt64) -> Bool {
        currentID == transitionID
    }
}

struct IslandWindowTransition: Equatable {
    let id: UInt64
    let targetShape: IslandShape
    let targetFrame: NSRect
}

enum IslandContentPresentationState: Equatable {
    case expanded
    case collapsed
}

struct IslandWindowTransitionState {
    private(set) var currentShape: IslandShape
    private(set) var restingShape: IslandShape
    private(set) var isExpansionActive = false
    private var tracker = IslandTransitionTracker()

    init(restingShape: IslandShape) {
        currentShape = restingShape
        self.restingShape = restingShape
    }

    mutating func reset(restingShape: IslandShape) {
        currentShape = restingShape
        self.restingShape = restingShape
        isExpansionActive = false
        invalidateTransitions()
    }

    mutating func updateRestingShape(_ shape: IslandShape) {
        restingShape = shape
    }

    mutating func setCurrentShape(_ shape: IslandShape) {
        currentShape = shape
    }

    @discardableResult
    mutating func activateExpansion(for trigger: CapsuleExpansionTrigger) -> Bool {
        guard !isExpansionActive else {
            return false
        }

        switch trigger {
        case .hover, .click:
            isExpansionActive = true
            currentShape = .expanded
        }
        return true
    }

    mutating func deactivateExpansion() {
        isExpansionActive = false
        currentShape = restingShape
    }

    mutating func beginTransition(
        size: NSSize,
        anchoredTo anchor: IslandWindowAnchor
    ) -> IslandWindowTransition {
        IslandWindowTransition(
            id: tracker.begin(),
            targetShape: currentShape,
            targetFrame: IslandWindowGeometry.frame(size: size, anchoredTo: anchor)
        )
    }

    mutating func invalidateTransitions() {
        _ = tracker.begin()
    }

    func isCurrentTransition(_ transitionID: UInt64) -> Bool {
        tracker.isCurrent(transitionID)
    }

    func settledPresentationState(
        for transitionID: UInt64,
        isDragging: Bool,
        isPressingForDrag: Bool
    ) -> IslandContentPresentationState? {
        guard tracker.isCurrent(transitionID),
              !isDragging,
              !isPressingForDrag else {
            return nil
        }

        if isExpansionActive, currentShape == .expanded {
            return .expanded
        }

        if !isExpansionActive, currentShape == restingShape {
            return .collapsed
        }

        return nil
    }
}

private final class IslandPositionStore {
    private let keyPrefix = "CodexIsland.NotchIsland.position"
    private let lastScreenKey = "CodexIsland.NotchIsland.position.lastScreenID"
    private let defaults = UserDefaults.standard

    func preferredScreen(in screens: [NSScreen]) -> NSScreen? {
        if let savedScreenID = defaults.string(forKey: lastScreenKey),
           let screen = screens.first(where: { $0.codexIslandIdentifier == savedScreenID }) {
            return screen
        }

        if let nonPrimaryScreen = screens.first(where: { screen in
            screen.frame.origin != .zero && hasSavedPosition(on: screen)
        }) {
            return nonPrimaryScreen
        }

        return screens.first { screen in
            hasSavedPosition(on: screen)
        }
    }

    func origin(for size: NSSize, on screen: NSScreen, usableFrame: NSRect) -> NSPoint? {
        guard let position = load(for: screen) else {
            return nil
        }

        guard position.reference != .origin else {
            reset(on: screen)
            return nil
        }

        return IslandPositionGeometry.origin(
            for: size,
            usableFrame: usableFrame,
            position: position
        )
    }

    func save(frame: NSRect, on screen: NSScreen, usableFrame: NSRect) {
        let position = IslandPositionGeometry.position(
            for: frame,
            usableFrame: usableFrame
        )

        if let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: key(for: screen))
            defaults.set(screen.codexIslandIdentifier, forKey: lastScreenKey)
        }
    }

    func reset(on screen: NSScreen) {
        defaults.removeObject(forKey: key(for: screen))
    }

    func resetAll() {
        for (key, _) in defaults.dictionaryRepresentation()
            where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: lastScreenKey)
    }

    private func hasSavedPosition(on screen: NSScreen) -> Bool {
        defaults.data(forKey: key(for: screen)) != nil
    }

    private func load(for screen: NSScreen) -> SavedIslandPosition? {
        guard let data = defaults.data(forKey: key(for: screen)) else {
            return nil
        }

        return try? JSONDecoder().decode(SavedIslandPosition.self, from: data)
    }

    private func key(for screen: NSScreen) -> String {
        if let displayID = screen.displayID {
            return "\(keyPrefix).\(displayID)"
        }

        return "\(keyPrefix).default"
    }
}

enum IslandPositionGeometry {
    static func position(for frame: NSRect, usableFrame: NSRect) -> SavedIslandPosition {
        let maxX = max(usableFrame.width, 1)
        let maxY = max(usableFrame.height, 1)

        return SavedIslandPosition(
            xRatio: (frame.midX - usableFrame.minX) / maxX,
            yRatio: (frame.maxY - usableFrame.minY) / maxY,
            reference: .topCenter
        )
    }

    static func origin(
        for size: NSSize,
        usableFrame: NSRect,
        position: SavedIslandPosition
    ) -> NSPoint {
        switch position.reference {
        case .origin:
            let maxX = max(usableFrame.width - size.width, 1)
            let maxY = max(usableFrame.height - size.height, 1)

            return NSPoint(
                x: usableFrame.minX + maxX * position.xRatio,
                y: usableFrame.minY + maxY * position.yRatio
            )
        case .center:
            let centerX = usableFrame.minX + usableFrame.width * position.xRatio
            let centerY = usableFrame.minY + usableFrame.height * position.yRatio

            return NSPoint(
                x: centerX - size.width / 2,
                y: centerY - size.height / 2
            )
        case .topCenter:
            let centerX = usableFrame.minX + usableFrame.width * position.xRatio
            let topY = usableFrame.minY + usableFrame.height * position.yRatio

            return NSPoint(
                x: centerX - size.width / 2,
                y: topY - size.height
            )
        }
    }
}

struct SavedIslandPosition: Codable, Equatable {
    let xRatio: CGFloat
    let yRatio: CGFloat
    let reference: Reference

    enum Reference: String, Codable, Equatable {
        case origin
        case center
        case topCenter
    }

    private enum CodingKeys: String, CodingKey {
        case xRatio
        case yRatio
        case reference
    }

    init(xRatio: CGFloat, yRatio: CGFloat, reference: Reference) {
        self.xRatio = xRatio
        self.yRatio = yRatio
        self.reference = reference
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        xRatio = try container.decode(CGFloat.self, forKey: .xRatio)
        yRatio = try container.decode(CGFloat.self, forKey: .yRatio)
        reference = try container.decodeIfPresent(Reference.self, forKey: .reference) ?? .origin
    }
}

private enum DragResistanceEdge {
    case minX
    case maxX
    case minY
    case maxY
}

private enum DragResistance {
    static let threshold: CGFloat = 28
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }

    var hasAuxiliaryTopAreas: Bool {
        guard let leftArea = auxiliaryTopLeftArea,
              let rightArea = auxiliaryTopRightArea else {
            return false
        }

        return leftArea.width > 0 && rightArea.width > 0
    }

    var codexIslandIdentifier: String {
        guard let displayID else {
            return "screen-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
        }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let name = localizedName
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: " ", with: "_")

        if vendor != 0 || model != 0 || serial != 0 {
            return "display-\(vendor)-\(model)-\(serial)-\(name)"
        }

        return "display-\(displayID)-\(name)"
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }

    func squaredDistance(to point: NSPoint) -> CGFloat {
        let dx: CGFloat
        if point.x < minX {
            dx = minX - point.x
        } else if point.x > maxX {
            dx = point.x - maxX
        } else {
            dx = 0
        }

        let dy: CGFloat
        if point.y < minY {
            dy = minY - point.y
        } else if point.y > maxY {
            dy = point.y - maxY
        } else {
            dy = 0
        }

        return dx * dx + dy * dy
    }
}

@MainActor
enum IslandHostingSizingPolicy {
    static func configure<Content: View>(_ hostingView: NSHostingView<Content>) {
        hostingView.sizingOptions = []
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }
}

private final class NotchIslandHostingView: NSHostingView<NotchIslandView> {
    var onHoverChanged: ((Bool) -> Void)?
    var onDragHandlePressed: ((NSEvent) -> Void)?

    private var hoverTrackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        if let trackingArea = hoverTrackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if interactionRegion(at: point) == .drag {
            return self
        }

        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard interactionRegion(at: localPoint) == .drag else {
            super.mouseDown(with: event)
            return
        }

        onDragHandlePressed?(event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func interactionRegion(at point: NSPoint) -> IslandInteractionRegion {
        IslandInteractionHitTest.region(for: point, in: bounds, isFlipped: isFlipped)
    }
}

enum IslandInteractionRegion: Equatable {
    case content
    case drag
    case headerControls
}

enum IslandInteractionHitTest {
    static let expandedHeaderHeight: CGFloat = 64
    static let headerControlsSize = CGSize(width: 194, height: 44)
    static let headerControlsInset: CGFloat = 10

    static func region(
        for point: NSPoint,
        in bounds: NSRect,
        isFlipped: Bool
    ) -> IslandInteractionRegion {
        guard bounds.contains(point) else {
            return .content
        }

        guard bounds.height >= 80 else {
            return .drag
        }

        if headerControlsFrame(in: bounds, isFlipped: isFlipped).contains(point) {
            return .headerControls
        }

        if headerFrame(in: bounds, isFlipped: isFlipped).contains(point) {
            return .drag
        }

        return .content
    }

    static func headerFrame(in bounds: NSRect, isFlipped: Bool) -> NSRect {
        let y = isFlipped ? bounds.minY : bounds.maxY - expandedHeaderHeight
        return NSRect(
            x: bounds.minX,
            y: y,
            width: bounds.width,
            height: expandedHeaderHeight
        )
    }

    static func headerControlsFrame(in bounds: NSRect, isFlipped: Bool) -> NSRect {
        let y = isFlipped
            ? bounds.minY + headerControlsInset
            : bounds.maxY - headerControlsInset - headerControlsSize.height
        return NSRect(
            x: bounds.maxX - headerControlsInset - headerControlsSize.width,
            y: y,
            width: headerControlsSize.width,
            height: headerControlsSize.height
        )
    }
}

enum IslandPressGesture {
    static let clickMovementThreshold: CGFloat = 4

    static func isClick(from start: NSPoint, to end: NSPoint) -> Bool {
        !isDrag(from: start, to: end)
    }

    static func isDrag(from start: NSPoint, to end: NSPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return dx * dx + dy * dy > clickMovementThreshold * clickMovementThreshold
    }
}
