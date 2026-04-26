import AppKit

/// Transparent borderless floating NSPanel for rendering underlines over target apps.
/// Uses .nonactivatingPanel so clicks don't steal focus from the target app.
@MainActor
final class OverlayWindow: NSPanel {

    /// Called on mouseDown events not consumed by a subview hit-test.
    /// Wired by OverlayController to dismiss on click-outside-underlines.
    var mouseDownHandler: (@MainActor (NSEvent) -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = true
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func mouseDown(with event: NSEvent) {
        mouseDownHandler?(event)
    }

}
