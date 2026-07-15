import AppKit
import SwiftUI

final class DesktopPetPanel: NSPanel {
    private var contextMenuCoordinator: DesktopPetContextMenuCoordinator?
    private var interactionPanel: DesktopPetInteractionPanel!

    init(controller: DesktopPetController) {
        super.init(
            contentRect: NSRect(origin: .zero, size: controller.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let hostingView = NSHostingView(
            rootView: DesktopPetView(controller: controller)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView

        let interactionPanel = DesktopPetInteractionPanel(windowSize: controller.windowSize)
        self.interactionPanel = interactionPanel
        interactionPanel.interactionView.onClick = { [weak controller] clickCount, screenLocation in
            controller?.handleClick(
                clickCount: clickCount,
                screenLocation: screenLocation
            )
        }
        interactionPanel.interactionView.onDragBegan = { [weak controller] screenLocation in
            controller?.handleDragBegan(screenLocation: screenLocation)
        }
        interactionPanel.interactionView.onDragChanged = { [weak controller] screenLocation in
            controller?.handleDragChanged(screenLocation: screenLocation)
        }
        interactionPanel.interactionView.onDragEnded = { [weak controller] screenLocation in
            controller?.handleDragEnded(screenLocation: screenLocation)
        }
        interactionPanel.interactionView.onResizeBegan = { [weak controller] screenLocation in
            controller?.handleResizeBegan(screenLocation: screenLocation)
        }
        interactionPanel.interactionView.onResizeChanged = { [weak controller] screenLocation in
            controller?.handleResizeChanged(screenLocation: screenLocation)
        }
        interactionPanel.interactionView.onResizeEnded = { [weak controller] screenLocation in
            controller?.handleResizeEnded(screenLocation: screenLocation)
        }
        interactionPanel.interactionView.onScrollResize = { [weak controller] deltaY, isPrecise, phaseEnded in
            controller?.handleScrollResize(
                deltaY: deltaY,
                isPrecise: isPrecise,
                phaseEnded: phaseEnded
            )
        }
        let contextMenuCoordinator = DesktopPetContextMenuCoordinator(controller: controller)
        self.contextMenuCoordinator = contextMenuCoordinator
        interactionPanel.interactionView.onRightClick = { [weak interactionPanel, weak contextMenuCoordinator] event in
            guard let interactionView = interactionPanel?.interactionView else {
                return
            }
            contextMenuCoordinator?.present(event: event, in: interactionView)
        }
        addChildWindow(interactionPanel, ordered: .above)
    }

    deinit {
        if let interactionPanel {
            removeChildWindow(interactionPanel)
        }
    }

    func updateInteractionRegion(
        _ layout: DesktopPetInteractionLayout,
        showsResizeHandle: Bool,
        resizeToolTip: String
    ) {
        guard let interactionPanel else {
            return
        }
        let bounds = layout.interactionBounds
        let screenFrame = CGRect(
            x: frame.minX + bounds.minX,
            y: frame.minY + bounds.minY,
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )
        interactionPanel.setFrame(screenFrame, display: true)
        interactionPanel.interactionView.configure(
            showsResizeHandle: showsResizeHandle,
            resizeToolTip: resizeToolTip
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DesktopPetInteractionPanel: NSPanel {
    let interactionView: DesktopPetInteractionView

    init(windowSize: CGSize) {
        interactionView = DesktopPetInteractionView(frame: CGRect(origin: .zero, size: windowSize))
        super.init(
            contentRect: CGRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        interactionView.autoresizingMask = [.width, .height]
        contentView = interactionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DesktopPetInteractionView: NSView {
    var onClick: ((Int, CGPoint) -> Void)?
    var onDragBegan: ((CGPoint) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    var onResizeBegan: ((CGPoint) -> Void)?
    var onResizeChanged: ((CGPoint) -> Void)?
    var onResizeEnded: ((CGPoint) -> Void)?
    var onScrollResize: ((CGFloat, Bool, Bool) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var mouseDownLocationInWindow: CGPoint?
    private var interactionMode: InteractionMode = .none
    private var isHovering = false
    private var allowsResizeHandle = false
    private var resizeToolTip = ""
    private var trackingAreaStorage: NSTrackingArea?

    override var isFlipped: Bool { false }

    func configure(showsResizeHandle: Bool, resizeToolTip: String) {
        allowsResizeHandle = showsResizeHandle
        self.resizeToolTip = resizeToolTip
        toolTip = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocationInWindow = event.locationInWindow
        if allowsResizeHandle, resizeHandleFrame.contains(event.locationInWindow) {
            interactionMode = .resize
            onResizeBegan?(screenLocation(for: event))
        } else {
            interactionMode = .clickCandidate
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let screenLocation = screenLocation(for: event)
        switch interactionMode {
        case .clickCandidate:
            interactionMode = .move
            onDragBegan?(screenLocation)
            onDragChanged?(screenLocation)
        case .move:
            onDragChanged?(screenLocation)
        case .resize:
            onResizeChanged?(screenLocation)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        let screenLocation = screenLocation(for: event)
        switch interactionMode {
        case .move:
            onDragEnded?(screenLocation)
        case .resize:
            onResizeEnded?(screenLocation)
        case .clickCandidate:
            onClick?(max(event.clickCount, 1), screenLocation)
        case .none:
            break
        }
        interactionMode = .none
        mouseDownLocationInWindow = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard allowsResizeHandle else {
            super.scrollWheel(with: event)
            return
        }
        let phaseEnded = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        let deltaY = event.scrollingDeltaY
        guard DesktopPetScrollScaling.acceptsEvent(
            deltaY: deltaY,
            hasMomentum: !event.momentumPhase.isEmpty,
            phaseEnded: phaseEnded
        ) else {
            return
        }
        onScrollResize?(deltaY, event.hasPreciseScrollingDeltas, phaseEnded)
    }

    override func updateTrackingAreas() {
        if let trackingAreaStorage {
            removeTrackingArea(trackingAreaStorage)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaStorage = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        guard interactionMode == .none else {
            return
        }
        isHovering = false
        toolTip = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let isOverHandle = allowsResizeHandle && resizeHandleFrame.contains(event.locationInWindow)
        toolTip = isOverHandle ? resizeToolTip : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard allowsResizeHandle, isHovering || interactionMode == .resize else {
            return
        }

        if let image = NSImage(
            systemSymbolName: DesktopPetInteractionGeometry.resizeHandleSymbolName,
            accessibilityDescription: resizeToolTip
        ) {
            image.isTemplate = true
            let imageRect = CGRect(
                x: resizeHandleFrame.midX - 7,
                y: resizeHandleFrame.midY - 7,
                width: 14,
                height: 14
            )
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.72)
            shadow.shadowBlurRadius = 2
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor(
                calibratedRed: 0.72,
                green: 0.98,
                blue: 0.96,
                alpha: interactionMode == .resize ? 1 : 0.92
            ).set()
            image.draw(in: imageRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func screenLocation(for event: NSEvent) -> CGPoint {
        guard let window = event.window else {
            return NSEvent.mouseLocation
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private var resizeHandleFrame: CGRect {
        DesktopPetInteractionGeometry.resizeHandleFrame(in: bounds)
    }

    private enum InteractionMode {
        case none
        case clickCandidate
        case move
        case resize
    }
}

enum DesktopPetContextMenuAction: String, Equatable {
    case openCodex
    case toggleFreeMovement
    case openCustomPets
    case openSettings
    case putAwayPet
}

struct DesktopPetContextMenuItemModel: Equatable {
    let title: String?
    let action: DesktopPetContextMenuAction?
    let isChecked: Bool

    static let separator = DesktopPetContextMenuItemModel(
        title: nil,
        action: nil,
        isChecked: false
    )
}

enum DesktopPetContextMenuModel {
    static func items(
        language: AppLanguage,
        isFreeMovementEnabled: Bool
    ) -> [DesktopPetContextMenuItemModel] {
        let titles: (String, String, String, String, String)
        switch language {
        case .chinese:
            titles = ("打开 Codex", "自由运动", "自定义宠物", "设置", "收回宠物")
        case .english:
            titles = ("Open Codex", "Free Movement", "Custom Pets", "Settings", "Put Away Pet")
        }

        return [
            DesktopPetContextMenuItemModel(
                title: titles.0,
                action: .openCodex,
                isChecked: false
            ),
            .separator,
            DesktopPetContextMenuItemModel(
                title: titles.1,
                action: .toggleFreeMovement,
                isChecked: isFreeMovementEnabled
            ),
            DesktopPetContextMenuItemModel(
                title: titles.2,
                action: .openCustomPets,
                isChecked: false
            ),
            DesktopPetContextMenuItemModel(
                title: titles.3,
                action: .openSettings,
                isChecked: false
            ),
            .separator,
            DesktopPetContextMenuItemModel(
                title: titles.4,
                action: .putAwayPet,
                isChecked: false
            )
        ]
    }
}

@MainActor
private final class DesktopPetContextMenuCoordinator: NSObject, NSMenuDelegate {
    private weak var controller: DesktopPetController?
    private let settings = AppSettingsStore.shared

    init(controller: DesktopPetController) {
        self.controller = controller
    }

    func present(event: NSEvent, in view: NSView) {
        guard controller?.contextMenuWillOpen() == true else {
            return
        }
        let menu = makeMenu()
        menu.delegate = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func menuDidClose(_ menu: NSMenu) {
        controller?.contextMenuDidClose()
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = DesktopPetContextMenuAction(rawValue: rawValue) else {
            return
        }

        switch action {
        case .openCodex:
            CodexActivation.activate()
        case .toggleFreeMovement:
            settings.isDesktopPetFreeMovementEnabled.toggle()
        case .openCustomPets:
            AppDirectories.open(CustomPetCatalog.shared.rootDirectory)
        case .openSettings:
            NotchIslandPanel.shared.presentSettings()
        case .putAwayPet:
            settings.isDesktopPetEnabled = false
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for itemModel in DesktopPetContextMenuModel.items(
            language: settings.language,
            isFreeMovementEnabled: settings.isDesktopPetFreeMovementEnabled
        ) {
            guard let title = itemModel.title,
                  let action = itemModel.action else {
                menu.addItem(.separator())
                continue
            }

            let item = NSMenuItem(
                title: title,
                action: #selector(performAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = action.rawValue
            item.state = itemModel.isChecked ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
}
