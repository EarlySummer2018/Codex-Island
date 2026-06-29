import AppKit
import Combine
import SwiftUI

final class NotchIslandPanel: NSPanel {
    static let shared = NotchIslandPanel()

    private let contentModel = NotchIslandContentModel()
    private let positionStore = IslandPositionStore()
    private let settings = AppSettingsStore.shared
    private var currentShape: IslandShape = .pill
    private var restingShape: IslandShape = .pill
    private var isHovered = false
    private var isPressingForDrag = false
    private var isDragging = false
    private var dragStartMouseLocation: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero
    private var cancellables = Set<AnyCancellable>()

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: IslandShape.pillSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

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

        let rootView = NotchIslandView(
            model: contentModel,
            onRestingShapeChanged: { [weak self] shape in
                self?.setRestingShape(shape)
            }
        )
        let hostingView = NotchIslandHostingView(rootView: rootView)
        hostingView.onHoverChanged = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        hostingView.onPressForDragChanged = { [weak self] pressing in
            self?.setPressingForDrag(pressing)
        }
        hostingView.onDragBegan = { [weak self] location in
            self?.beginDrag(at: location)
        }
        hostingView.onDragChanged = { [weak self] location in
            self?.drag(to: location)
        }
        hostingView.onDragEnded = { [weak self] in
            self?.endDrag()
        }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView

        observeSettings()
        relayout(animated: false)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        guard settings.isCapsuleVisible else {
            orderOut(nil)
            return
        }

        relayout(animated: false)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    func transition(
        to shape: IslandShape,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        currentShape = shape
        relayout(animated: animated, completion: completion)
    }

    func resetPosition() {
        if let screen = targetScreen() {
            positionStore.reset(on: screen)
        } else {
            positionStore.resetAll()
        }
        relayout(animated: true)
    }

    private func observeSettings() {
        settings.$capsuleStyle
            .dropFirst()
            .sink { [weak self] _ in
                self?.relayout(animated: true)
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
    }

    private func setRestingShape(_ shape: IslandShape) {
        restingShape = shape

        if !isHovered {
            transition(to: shape)
        }
    }

    private func setHovered(_ hovered: Bool) {
        guard !isDragging, !isPressingForDrag else {
            return
        }

        if !hovered {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.syncHoverStateWithMouseLocation()
            }
            return
        }

        guard !isHovered else {
            return
        }

        expandForHover()
    }

    private func syncHoverStateWithMouseLocation() {
        guard !isDragging, !isPressingForDrag else {
            return
        }

        let isMouseInside = frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)

        if isMouseInside {
            if !isHovered {
                expandForHover()
            } else {
                transition(to: .expanded)
            }
            return
        }

        guard isHovered else {
            return
        }

        collapseFromHover()
    }

    private func expandForHover() {
        isHovered = true
        contentModel.isExpanded = false
        contentModel.isExpandedContainer = true

        transition(to: .expanded) { [weak self] in
            guard let self,
                  self.isHovered,
                  self.currentShape == .expanded,
                  !self.isDragging,
                  !self.isPressingForDrag else {
                return
            }

            self.contentModel.isExpanded = true
        }
    }

    private func collapseFromHover() {
        isHovered = false
        contentModel.isExpanded = false
        transition(to: restingShape) { [weak self] in
            guard let self,
                  !self.isHovered,
                  self.currentShape == self.restingShape else {
                return
            }

            self.contentModel.isExpandedContainer = false
        }
    }

    @objc private func screenParametersChanged() {
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

    private func beginDrag(at location: NSPoint) {
        isDragging = true
        dragStartMouseLocation = location
        dragStartFrame = frame
    }

    private func drag(to location: NSPoint) {
        guard isDragging,
              let screen = screen(containing: dragStartFrame) ?? targetScreen() else {
            return
        }

        let deltaX = location.x - dragStartMouseLocation.x
        let deltaY = location.y - dragStartMouseLocation.y
        let proposedFrame = dragStartFrame.offsetBy(dx: deltaX, dy: deltaY)
        setFrame(clampedFrame(proposedFrame, on: screen), display: true)
    }

    private func endDrag() {
        guard isDragging else {
            return
        }

        isDragging = false
        isPressingForDrag = false

        if let screen = screen(containing: frame) ?? targetScreen() {
            positionStore.save(frame: frame, on: screen)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.syncHoverStateWithMouseLocation()
        }
    }

    private func relayout(animated: Bool, completion: (() -> Void)? = nil) {
        guard settings.isCapsuleVisible else {
            orderOut(nil)
            completion?()
            return
        }

        guard let screen = targetScreen() else {
            completion?()
            return
        }

        let notchFrame = calculateNotchFrame(for: screen)
        let proposedWindowFrame = calculateWindowFrame(
            shape: currentShape,
            notchFrame: notchFrame,
            screen: screen
        )
        let windowFrame = clampedFrame(
            frameAnchoredToCurrentTopEdgeWhenVisible(
                proposedWindowFrame,
                on: screen
            ),
            on: screen
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = currentShape == .expanded ? 0.30 : 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(windowFrame, display: true)
            } completionHandler: {
                completion?()
            }
        } else {
            setFrame(windowFrame, display: true)
            completion?()
        }
    }

    private func targetScreen() -> NSScreen? {
        if let builtInScreen = NSScreen.screens.first(where: { screen in
            guard let displayID = screen.displayID else {
                return false
            }
            return CGDisplayIsBuiltin(displayID) != 0
        }) {
            return builtInScreen
        }

        if let notchedScreen = NSScreen.screens.first(where: { screen in
            screen.hasAuxiliaryTopAreas
        }) {
            return notchedScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
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
        NSRect(
            x: screen.frame.midX - IslandShape.fallbackCompactSize.width / 2,
            y: screen.frame.maxY - IslandShape.fallbackCompactSize.height,
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
        var size = shape.size(fitting: notchFrame, capsuleStyle: settings.capsuleStyle)
        size.width = min(size.width, screen.frame.width)
        size.height = min(size.height, screen.frame.height - IslandShape.topInset)

        let x = clampedX(
            centeredAt: notchFrame.midX,
            width: size.width,
            screen: screen
        )

        if let savedOrigin = positionStore.origin(for: size, on: screen) {
            return NSRect(origin: savedOrigin, size: size)
        }

        switch shape {
        case .compact, .pill:
            return NSRect(
                x: x,
                y: screen.frame.maxY - IslandShape.topInset - size.height,
                width: size.width,
                height: size.height
            )
        case .expanded:
            return NSRect(
                x: x,
                y: screen.frame.maxY - IslandShape.topInset - size.height,
                width: size.width,
                height: size.height
            )
        }
    }

    private func clampedX(centeredAt centerX: CGFloat, width: CGFloat, screen: NSScreen) -> CGFloat {
        let proposedX = centerX - width / 2
        let minX = screen.frame.minX
        let maxX = screen.frame.maxX - width
        return min(max(proposedX, minX), maxX)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { screen in
            screen.frame.contains(center)
        }
    }

    private func clampedFrame(_ frame: NSRect, on screen: NSScreen) -> NSRect {
        let minX = screen.frame.minX
        let maxX = screen.frame.maxX - frame.width
        let minY = screen.frame.minY
        let maxY = screen.frame.maxY - frame.height

        return NSRect(
            x: min(max(frame.minX, minX), maxX),
            y: min(max(frame.minY, minY), maxY),
            width: frame.width,
            height: frame.height
        )
    }

    private func frameAnchoredToCurrentTopEdgeWhenVisible(
        _ proposedFrame: NSRect,
        on screen: NSScreen
    ) -> NSRect {
        let currentFrame = frame
        let currentCenter = NSPoint(x: currentFrame.midX, y: currentFrame.midY)

        guard isVisible,
              currentFrame.width > 0,
              currentFrame.height > 0,
              screen.frame.contains(currentCenter) else {
            return proposedFrame
        }

        return NSRect(
            x: currentFrame.midX - proposedFrame.width / 2,
            y: currentFrame.maxY - proposedFrame.height,
            width: proposedFrame.width,
            height: proposedFrame.height
        )
    }
}

private final class IslandPositionStore {
    private let keyPrefix = "CodexIsland.NotchIsland.position"
    private let defaults = UserDefaults.standard

    func origin(for size: NSSize, on screen: NSScreen) -> NSPoint? {
        guard let position = load(for: screen) else {
            return nil
        }

        let maxX = max(screen.frame.width - size.width, 1)
        let maxY = max(screen.frame.height - size.height, 1)

        return NSPoint(
            x: screen.frame.minX + maxX * position.xRatio,
            y: screen.frame.minY + maxY * position.yRatio
        )
    }

    func save(frame: NSRect, on screen: NSScreen) {
        let maxX = max(screen.frame.width - frame.width, 1)
        let maxY = max(screen.frame.height - frame.height, 1)
        let position = SavedIslandPosition(
            xRatio: min(max((frame.minX - screen.frame.minX) / maxX, 0), 1),
            yRatio: min(max((frame.minY - screen.frame.minY) / maxY, 0), 1)
        )

        if let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: key(for: screen))
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

private struct SavedIslandPosition: Codable {
    let xRatio: CGFloat
    let yRatio: CGFloat
}

private extension NSScreen {
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
}

private final class NotchIslandHostingView: NSHostingView<NotchIslandView> {
    var onHoverChanged: ((Bool) -> Void)?
    var onPressForDragChanged: ((Bool) -> Void)?
    var onDragBegan: ((NSPoint) -> Void)?
    var onDragChanged: ((NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var hoverTrackingArea: NSTrackingArea?
    private let dragLongPressDuration: TimeInterval = 0.35

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

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard isDragHandlePoint(localPoint) else {
            super.mouseDown(with: event)
            return
        }

        trackDragHandlePress(startEvent: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func trackDragHandlePress(startEvent: NSEvent) {
        guard let window else {
            return
        }

        onPressForDragChanged?(true)
        let startLocation = screenLocation(for: startEvent)
        let longPressDeadline = Date().addingTimeInterval(dragLongPressDuration)
        var hasBegunDrag = false
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]

        while true {
            if !hasBegunDrag, Date() >= longPressDeadline {
                hasBegunDrag = true
                onDragBegan?(startLocation)
            }

            let nextDeadline = hasBegunDrag ? Date.distantFuture : longPressDeadline
            guard let nextEvent = window.nextEvent(
                matching: eventMask,
                until: nextDeadline,
                inMode: .eventTracking,
                dequeue: true
            ) else {
                continue
            }

            switch nextEvent.type {
            case .leftMouseDragged:
                if hasBegunDrag {
                    onDragChanged?(screenLocation(for: nextEvent))
                }
            case .leftMouseUp:
                if hasBegunDrag {
                    onDragEnded?()
                } else {
                    onPressForDragChanged?(false)
                }
                return
            default:
                break
            }
        }
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else {
            return NSEvent.mouseLocation
        }

        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }

    private func isDragHandlePoint(_ point: NSPoint) -> Bool {
        guard bounds.height >= 80 else {
            return false
        }

        let handleWidth = min(max(bounds.width * 0.22, 76), 112)
        let handleHeight: CGFloat = 58
        let handleFrame = NSRect(
            x: bounds.maxX - handleWidth - 10,
            y: bounds.maxY - handleHeight - 4,
            width: handleWidth,
            height: handleHeight
        )

        return handleFrame.contains(point)
    }
}
