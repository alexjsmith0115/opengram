import AppKit

/// Transparent borderless floating NSWindow for rendering underlines over target apps.
/// Non-activating by default (collectionBehavior), but canBecomeKey for keyboard navigation.
@MainActor
final class OverlayWindow: NSWindow {
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
}
