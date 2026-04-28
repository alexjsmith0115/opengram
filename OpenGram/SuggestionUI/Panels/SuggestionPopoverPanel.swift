import AppKit

/// Non-activating NSPanel for displaying suggestion details.
/// Borderless panel (no .hudWindow) — SwiftUI renders the full opaque card background (D-06).
@MainActor
final class SuggestionPopoverPanel: NSPanel {
    private static let minHeight: CGFloat = 120

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
        SuggestionPopoverCardChrome.configurePanel(self)
    }

    override var canBecomeKey: Bool { false }

    /// Positions and shows the panel near an underline rect on the given screen.
    /// Prefers appearing above the underline; flips below if insufficient space.
    /// Clamps to screen visible frame to prevent panel from going off-screen.
    func showNear(underlineRect: NSRect, on screen: NSScreen) {
        let size = NSSize(
            width: min(max(frame.width, SuggestionPopoverCardChrome.minPanelWidth), SuggestionPopoverCardChrome.maxPanelWidth),
            height: max(frame.height, Self.minHeight)
        )
        let origin = PanelPositioner.origin(for: size, near: underlineRect, on: screen)
        setFrame(NSRect(origin: origin, size: size), display: false)
        orderFront(nil)
    }

    func setContent(_ view: NSView) {
        contentView = view
        SuggestionPopoverCardChrome.configureHostedContent(view)
        view.layoutSubtreeIfNeeded()

        let fitting = view.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return }

        let contentSize = SuggestionPopoverCardChrome.panelContentSize(for: fitting, minHeight: Self.minHeight)
        setContentSize(contentSize)
    }
}
