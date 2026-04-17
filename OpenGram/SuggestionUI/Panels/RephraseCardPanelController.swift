@preconcurrency import ApplicationServices
import AppKit
import SwiftUI

/// Phase 18 D-06: hosts `RephraseCardView` in a non-activating NSPanel, mirroring
/// LLMPanelController's pattern (76-line template). Coexists with LLMPanelController.
/// Owns subscriptions for click-outside hide (resignKey) and FR-18 edit-closes
/// (TextMonitor.onKeystroke → caret-in-paragraph check).
@MainActor
final class RephraseCardPanelController {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<RephraseCardView>?
    private var scrollWrapper: NSScrollView?
    private var resignObserver: NSObjectProtocol?

    private static let verticalSafeMargin: CGFloat = 40

    /// Test-only hook. Internal (not public) — `@testable import OpenGramLib` grants access
    /// to Plan 03 D-11 test cases that need to inspect panel.contentView type and panel.frame size.
    /// Read-only; production code does not consume it.
    internal var testHookPanel: NSPanel? { panel }

    // Captured for the keystroke callback's caret-containment check.
    private var currentAXElement: AXUIElement?
    private var currentParagraphRange: (scalarStart: Int, scalarLength: Int)?
    private var previousKeystroke: (@MainActor () -> Void)?
    private weak var textMonitorRef: TextMonitor?

    /// Caller-provided hook that fires on any hide path (resignKey, edit-closes, Accept, Dismiss).
    private var onHide: (@MainActor () -> Void)?

    /// Presents the card. Accept / Dismiss callbacks are baked into the ViewModel by the caller.
    /// The controller layers on top:
    ///   - resignKey → hide + onHide
    ///   - TextMonitor.onKeystroke → caret-in-paragraph check → hide + onHide
    /// `paragraphScalarRange` is the scalar-offset range of `paragraph.range` within the
    /// source text (caller computes once at show-time to avoid per-keystroke cost).
    func show(
        viewModel: RephraseCardViewModel,
        near anchorRect: NSRect,
        on screen: NSScreen,
        axElement: AXUIElement,
        paragraphScalarRange: (scalarStart: Int, scalarLength: Int),
        textMonitor: TextMonitor,
        onHide: @escaping @MainActor () -> Void
    ) {
        // Tear down any prior card first (single active card — D-06 one at a time).
        self.hide()

        self.onHide = onHide
        self.currentAXElement = axElement
        self.currentParagraphRange = paragraphScalarRange
        self.textMonitorRef = textMonitor

        let hosting = NSHostingView(rootView: RephraseCardView(viewModel: viewModel))

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isFloatingPanel = true
        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.canJoinAllSpaces]
        newPanel.isMovableByWindowBackground = true
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = false   // SwiftUI card provides its own shadow via RoundedRectangle

        // Force layout so fittingSize is valid (Phase 11 learning — see LLMPanelController.swift:53-59).
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize

        // D-10: 200pt defensive floor guards against fittingSize glitches returning 0.
        let flooredSize = NSSize(
            width: max(fitting.width, 380),
            height: max(fitting.height, 200)
        )

        // D-09: cap height at visibleFrame.height - verticalSafeMargin before positioning.
        let capped = PanelPositioner.capHeight(
            flooredSize,
            visibleFrame: screen.visibleFrame,
            margin: Self.verticalSafeMargin
        )

        // D-04/D-05: conditional scroll wrapper — overflow-only.
        if capped.height < flooredSize.height {
            let scroll = NSScrollView(frame: .zero)
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.documentView = hosting
            newPanel.contentView = scroll
            self.scrollWrapper = scroll
        } else {
            newPanel.contentView = hosting
        }

        newPanel.setContentSize(capped)

        let panelOrigin = PanelPositioner.marginOrigin(for: newPanel.frame.size, near: anchorRect, on: screen, gap: 12)
        newPanel.setFrameOrigin(panelOrigin)
        newPanel.orderFront(nil)

        self.panel = newPanel
        self.hostingView = hosting

        // resignKey — click-outside hide (D-08).
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }

        // TextMonitor.onKeystroke subscription — FR-18 edit-closes (D-09).
        // Closure-chaining preserves any prior subscriber (research A3 sole-subscriber note).
        self.previousKeystroke = textMonitor.onKeystroke
        textMonitor.onKeystroke = { [weak self] in
            self?.previousKeystroke?()
            self?.handleKeystroke()
        }
    }

    /// Tears down panel + subscriptions. Safe to call multiple times.
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        scrollWrapper = nil   // D-05 teardown symmetry

        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }

        // Restore prior keystroke callback so other subscribers survive.
        if let monitor = textMonitorRef {
            monitor.onKeystroke = previousKeystroke
        }
        previousKeystroke = nil
        textMonitorRef = nil

        currentAXElement = nil
        currentParagraphRange = nil

        let callback = onHide
        onHide = nil
        callback?()
    }

    // MARK: - Edit-closes

    /// Queries the target AX element's selected-text range. If the caret (location) falls
    /// within the card's paragraph scalar range, the card hides (FR-18 edit-closes).
    private func handleKeystroke() {
        guard let element = currentAXElement,
              let para = currentParagraphRange else { return }

        var rangeRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard err == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return }

        let caret = cfRange.location
        let paragraphEnd = para.scalarStart + para.scalarLength
        if caret >= para.scalarStart && caret <= paragraphEnd {
            hide()
        }
    }
}
