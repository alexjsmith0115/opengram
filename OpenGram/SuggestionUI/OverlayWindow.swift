import AppKit

/// Transparent borderless floating NSWindow for rendering underlines over target apps.
/// Non-activating by default (collectionBehavior), but canBecomeKey for keyboard navigation.
@MainActor
final class OverlayWindow: NSWindow {

    /// Called on keyDown events. Wired by OverlayController to handle Escape and Tab navigation.
    var keyHandler: (@MainActor (NSEvent) -> Void)?

    /// Called on mouseDown events not consumed by a subview hit-test.
    /// Wired by OverlayController to dismiss on click-outside-underlines.
    var mouseDownHandler: (@MainActor (NSEvent) -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        hasShadow = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        keyHandler?(event)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownHandler?(event)
    }
}
