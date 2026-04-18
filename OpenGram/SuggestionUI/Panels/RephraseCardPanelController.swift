@preconcurrency import ApplicationServices
import AppKit
import os.log
import SwiftUI

/// D-06: hosts `RephraseCardView` in a non-activating NSPanel.
/// Owns subscriptions for click-outside hide (resignKey) and FR-18 edit-closes
/// (TextMonitor.onKeystroke → caret-in-paragraph check).
@MainActor
final class RephraseCardPanelController {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "RephraseCardPanel"
    )

    private var panel: NSPanel?
    private var hostingView: NSHostingView<RephraseCardView>?
    private var scrollWrapper: NSScrollView?
    private var resignObserver: NSObjectProtocol?

    private static let verticalSafeMargin: CGFloat = 40

    /// Test-only hook. Internal (not public) — `@testable import OpenGramLib` grants access
    /// to D-11 test cases that need to inspect panel.contentView type and panel.frame size.
    /// Read-only; production code does not consume it.
    internal var testHookPanel: NSPanel? { panel }

    /// Test-only seam. Overrides the fittingSize measurement so tests can force the overflow
    /// branch without requiring a real display (headless NSHostingView always returns idealHeight).
    /// Nil in production — the real fittingSize path runs.
    internal var testHookFittingSize: NSSize?

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
        Self.logger.info("show() entry — anchorRect=\(NSStringFromRect(anchorRect)) screen.visibleFrame=\(NSStringFromRect(screen.visibleFrame))")

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

        // Attach hosting to panel before layout so SwiftUI has a window context for fittingSize.
        newPanel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // testHookFittingSize lets tests force the overflow branch; headless NSHostingView always
        // returns idealHeight so real text-length-driven overflow cannot be observed without a display.
        let fitting = testHookFittingSize ?? hosting.fittingSize

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

        Self.logger.info("sizing — fitting=\(NSStringFromSize(fitting)) floored=\(NSStringFromSize(flooredSize)) capped=\(NSStringFromSize(capped))")

        // D-04/D-05: conditional scroll wrapper — overflow-only. Reassign contentView if needed.
        if capped.height < flooredSize.height {
            Self.logger.info("overflow branch — wrapping hosting in NSScrollView")
            let scroll = NSScrollView(frame: .zero)
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.documentView = hosting
            newPanel.contentView = scroll
            self.scrollWrapper = scroll
        } else {
            Self.logger.info("short-content branch — plain NSHostingView")
        }

        newPanel.setContentSize(capped)

        let panelOrigin = PanelPositioner.marginOrigin(for: newPanel.frame.size, near: anchorRect, on: screen, gap: 12)
        newPanel.setFrameOrigin(panelOrigin)
        Self.logger.info("panel frame=\(NSStringFromRect(newPanel.frame)) — ordering front")
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
