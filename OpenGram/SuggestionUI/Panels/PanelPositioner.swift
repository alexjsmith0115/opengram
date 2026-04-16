import AppKit

/// Shared positioning logic for non-activating panels (suggestion popover, LLM panel).
/// Prefers above the anchor rect; flips below if insufficient space. Clamps to screen.
enum PanelPositioner {

    /// Computes the origin for a panel of `size` positioned near `anchorRect` on `screen`.
    /// `gap` is the vertical distance between anchor and panel edge.
    static func origin(
        for size: NSSize,
        near anchorRect: NSRect,
        on screen: NSScreen,
        gap: CGFloat = 4
    ) -> NSPoint {
        let visibleFrame = screen.visibleFrame

        // Prefer above anchor
        var origin = NSPoint(
            x: anchorRect.midX - size.width / 2,
            y: anchorRect.maxY + gap
        )

        // Flip below if not enough space above
        if origin.y + size.height > visibleFrame.maxY {
            origin.y = anchorRect.minY - size.height - gap
        }

        // Clamp horizontally
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - size.width))
        // Clamp vertically
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - size.height))

        return origin
    }
}
