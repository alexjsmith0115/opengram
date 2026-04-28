import AppKit

/// NSPanel subclass for the rewrite window. Allows the panel to take key-window
/// status without activating the source app, and routes ⌘↵ + Esc to the controller.
final class RewriteHostPanel: NSPanel {
    var onCommandReturn: (() -> Void)?
    var onCancelOp: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        hasShadow = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        animationBehavior = .utilityWindow
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""
        if mods == .command && chars == "\r" {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancelOp?()
    }
}
