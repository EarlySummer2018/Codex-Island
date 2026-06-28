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

    func transition(to shape: IslandShape, animated: Bool = true) {
        currentShape = shape
        relayout(animated: animated)
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

        isHovered = true
        contentModel.isExpanded = true
        transition(to: .expanded)
    }

    private func syncHoverStateWithMouseLocation() {
        guard !isDragging, !isPressingForDrag else {
            return
        }

        let isMouseInside = frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)

        if isMouseInside {
            if !isHovered {
                isHovered = true
                contentModel.isExpanded = true
            }
            transition(to: .expanded)
            return
        }

        guard isHovered else {
            return
        }

        isHovered = false
        contentModel.isExpanded = false
        transition(to: restingShape)
    }

    @objc private func screenParametersChanged() {
        relayout(animated: false)
    }

    private func setPressingForDrag(_ pressing: Bool) {
        isPressingForDrag = pressing

        if pressing {
            contentModel.isExpanded = false
            transition(to: restingShape, animated: true)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.syncHoverStateWithMouseLocation()
            }
        }
    }

    private func beginDrag(at location: NSPoint) {
        isDragging = true
        dragStartMouseLocation = location
        dragStartFrame = frame
        contentModel.isExpanded = false
        transition(to: restingShape, animated: false)
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

    private func relayout(animated: Bool) {
        guard settings.isCapsuleVisible else {
            orderOut(nil)
            return
        }

        guard let screen = targetScreen() else {
            return
        }

        let notchFrame = calculateNotchFrame(for: screen)
        let windowFrame = calculateWindowFrame(
            shape: currentShape,
            notchFrame: notchFrame,
            screen: screen
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = currentShape == .expanded ? 0.30 : 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(windowFrame, display: true)
            }
        } else {
            setFrame(windowFrame, display: true)
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
            return clampedFrame(
                NSRect(origin: savedOrigin, size: size),
                on: screen
            )
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
    private var longPressWorkItem: DispatchWorkItem?
    private var isLongPressDragging = false

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
        onPressForDragChanged?(true)
        let startLocation = NSEvent.mouseLocation
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.isLongPressDragging = true
            self.onDragBegan?(startLocation)
        }

        longPressWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isLongPressDragging else {
            return
        }

        onDragChanged?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil

        if isLongPressDragging {
            isLongPressDragging = false
            onDragEnded?()
        } else {
            onPressForDragChanged?(false)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
