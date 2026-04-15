import AppKit
import SwiftUI

/// Hosts LLMSuggestionPanel in a non-activating NSPanel, following the SuggestionPopoverPanel pattern.
/// Call show(suggestions:context:near:) to display; dismiss() to hide.
@MainActor
final class LLMPanelController {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<LLMSuggestionPanel>?

    func show(
        suggestions: [LLMStyleSuggestion],
        near anchorRect: NSRect,
        on screen: NSScreen,
        onApply: @escaping @MainActor (LLMStyleSuggestion) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        guard !suggestions.isEmpty else { return }

        dismiss()

        let panelView = LLMSuggestionPanel(
            suggestions: suggestions,
            onApply: { [weak self] suggestion in
                onApply(suggestion)
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                onDismiss()
                self?.dismiss()
            }
        )

        let hosting = NSHostingView(rootView: panelView)
        hosting.sizingOptions = .preferredContentSize

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        newPanel.isMovableByWindowBackground = false
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false  // SwiftUI card provides its own shadow
        newPanel.contentView = hosting

        // Size the panel to fit content
        newPanel.setContentSize(hosting.intrinsicContentSize)

        position(panel: newPanel, near: anchorRect, on: screen)
        newPanel.orderFront(nil)

        self.panel = newPanel
        self.hostingView = hosting
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: - Positioning

    private func position(panel: NSPanel, near anchorRect: NSRect, on screen: NSScreen) {
        let size = panel.frame.size
        let gap: CGFloat = 8
        let visibleFrame = screen.visibleFrame

        // Prefer above the anchor rect
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

        panel.setFrameOrigin(origin)
    }
}
