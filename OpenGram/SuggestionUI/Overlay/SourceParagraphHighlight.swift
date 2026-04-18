import AppKit

/// FR-13 / D-10: light-blue translucent background rendered in the overlay window
/// behind the target paragraph while the rephrase card is visible. Non-interactive — clicks
/// pass through to the target app. The caller (OverlayController) sizes and positions this
/// against AX line-rects for the paragraph.
final class SourceParagraphHighlight: NSView {

    private static let fillColor = NSColor.systemBlue.withAlphaComponent(0.08)
    private static let cornerRadius: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = Self.fillColor.cgColor
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
    }

    /// Non-interactive. Clicks always pass through to underlying windows.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
