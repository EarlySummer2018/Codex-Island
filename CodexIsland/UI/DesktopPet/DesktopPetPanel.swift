import AppKit
import SwiftUI

final class DesktopPetPanel: NSPanel {
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
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        let hostingView = DesktopPetHostingView(
            rootView: DesktopPetView(controller: controller)
        )
        hostingView.onClick = { [weak controller] clickCount, screenLocation in
            controller?.handleClick(
                clickCount: clickCount,
                screenLocation: screenLocation
            )
        }
        hostingView.onDragBegan = { [weak controller] screenLocation, offsetInWindow in
            controller?.handleDragBegan(
                screenLocation: screenLocation,
                offsetInWindow: offsetInWindow
            )
        }
        hostingView.onDragChanged = { [weak controller] screenLocation in
            controller?.handleDragChanged(screenLocation: screenLocation)
        }
        hostingView.onDragEnded = { [weak controller] screenLocation in
            controller?.handleDragEnded(screenLocation: screenLocation)
        }
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DesktopPetHostingView: NSHostingView<DesktopPetView> {
    var onClick: ((Int, CGPoint) -> Void)?
    var onDragBegan: ((CGPoint, CGPoint) -> Void)?
    var onDragChanged: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?

    private var mouseDownLocationInWindow: CGPoint?
    private var isDraggingPet = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocationInWindow = event.locationInWindow
        isDraggingPet = false
    }

    override func mouseDragged(with event: NSEvent) {
        let screenLocation = screenLocation(for: event)
        let offset = mouseDownLocationInWindow ?? event.locationInWindow

        if !isDraggingPet {
            isDraggingPet = true
            onDragBegan?(screenLocation, offset)
        }

        onDragChanged?(screenLocation)
    }

    override func mouseUp(with event: NSEvent) {
        let screenLocation = screenLocation(for: event)

        if isDraggingPet {
            onDragEnded?(screenLocation)
        } else {
            onClick?(max(event.clickCount, 1), screenLocation)
        }

        isDraggingPet = false
        mouseDownLocationInWindow = nil
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
}
