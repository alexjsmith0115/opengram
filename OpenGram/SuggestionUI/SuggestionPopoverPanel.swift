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
        isMovableByWindowBackground = false
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
        let contentWidth: CGFloat = min(max(frame.width, 280), 360)
        let contentHeight: CGFloat = frame.height

        let gap: CGFloat = 4
        var origin = NSPoint(
            x: underlineRect.midX - contentWidth / 2,
            y: underlineRect.maxY + gap
        )

        let visibleFrame = screen.visibleFrame

        // Flip below if not enough space above
        if origin.y + contentHeight > visibleFrame.maxY {
            origin.y = underlineRect.minY - contentHeight - gap
        }

        // Clamp horizontally
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - contentWidth))
        // Clamp vertically
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - contentHeight))

        let panelRect = NSRect(origin: origin, size: NSSize(width: contentWidth, height: contentHeight))
        setFrame(panelRect, display: false)
        orderFront(nil)
    }

    func setContent(_ view: NSView) {
        contentView = view
    }
}
