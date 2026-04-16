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

        // Force layout so intrinsicContentSize is valid, then size panel to fit
        hosting.layoutSubtreeIfNeeded()
        let fittingSize = hosting.fittingSize
        let size = NSSize(
            width: max(fittingSize.width, 360),
            height: max(fittingSize.height, 100)
        )
        newPanel.setContentSize(size)

        let panelOrigin = PanelPositioner.origin(for: newPanel.frame.size, near: anchorRect, on: screen, gap: 8)
        newPanel.setFrameOrigin(panelOrigin)
        newPanel.orderFront(nil)

        self.panel = newPanel
        self.hostingView = hosting
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

}
