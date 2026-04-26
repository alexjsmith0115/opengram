import AppKit

/// Non-activating NSPanel for displaying suggestion details.
/// Borderless panel (no .hudWindow) — SwiftUI renders the full opaque card background (D-06).
@MainActor
final class SuggestionPopoverPanel: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces]
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        // SwiftUI renders the background via RoundedRectangle; panel is transparent beneath it.
        backgroundColor = .clear
        // Belt-and-suspenders: NSPanel system shadow in addition to SwiftUI shadow.
        hasShadow = true
    }

    override var canBecomeKey: Bool { false }

    /// Positions and shows the panel near an underline rect on the given screen.
    /// Prefers appearing above the underline; flips below if insufficient space.
    /// Clamps to screen visible frame to prevent panel from going off-screen.
    func showNear(underlineRect: NSRect, on screen: NSScreen) {
        let size = NSSize(
            width: min(max(frame.width, 280), 360),
            height: frame.height
        )
        let origin = PanelPositioner.origin(for: size, near: underlineRect, on: screen)
        setFrame(NSRect(origin: origin, size: size), display: false)
        orderFront(nil)
    }

    func setContent(_ view: NSView) {
        contentView = view
    }
}
