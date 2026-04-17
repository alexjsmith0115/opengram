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

    /// Positions panel in the margin — prefers right of anchor, falls back to left, then above/below.
    /// Vertically centers panel against anchor rect.
    static func marginOrigin(
        for size: NSSize,
        near anchorRect: NSRect,
        on screen: NSScreen,
        gap: CGFloat = 8
    ) -> NSPoint {
        let visibleFrame = screen.visibleFrame
        let verticalY = clampedY(anchorMidY: anchorRect.midY, panelHeight: size.height, visibleFrame: visibleFrame)

        // Prefer right margin
        let rightX = anchorRect.maxX + gap
        if rightX + size.width <= visibleFrame.maxX {
            return NSPoint(x: rightX, y: verticalY)
        }

        // Fall back to left margin
        let leftX = anchorRect.minX - size.width - gap
        if leftX >= visibleFrame.minX {
            return NSPoint(x: leftX, y: verticalY)
        }

        // Neither margin fits — fall back to above/below
        return origin(for: size, near: anchorRect, on: screen, gap: gap)
    }

    /// Caps `size.height` to `visibleFrame.height - margin`. Width unchanged.
    /// D-08 (option a) — explicit, single-purpose, opt-in. Callers invoke before
    /// `origin(...)` / `marginOrigin(...)` to guarantee the resulting Y+height
    /// stays inside `visibleFrame`. Not required by all panel callers.
    static func capHeight(
        _ size: NSSize,
        visibleFrame: NSRect,
        margin: CGFloat
    ) -> NSSize {
        let maxHeight = visibleFrame.height - margin
        return NSSize(width: size.width, height: min(size.height, maxHeight))
    }

    private static func clampedY(anchorMidY: CGFloat, panelHeight: CGFloat, visibleFrame: NSRect) -> CGFloat {
        let y = anchorMidY - panelHeight / 2
        return max(visibleFrame.minY, min(y, visibleFrame.maxY - panelHeight))
    }
}
