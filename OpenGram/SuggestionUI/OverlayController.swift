@preconcurrency import ApplicationServices
import AppKit
import SwiftUI

/// Coordinates the overlay window and suggestion popover.
/// Owns the OverlayWindow, SuggestionPopoverPanel, TargetAppObserver, and scroll monitor.
/// Plans 02 and 03 extend this class with popover, dismissal, and write-back.
@MainActor
final class OverlayController {

    // T-03-02: cap displayed suggestions to prevent blocking the main thread with AX queries
    private static let maxDisplayedSuggestions = 50

    private let accessor: any AXAccessor
    private let overlayWindow: OverlayWindow
    private let popoverPanel: SuggestionPopoverPanel
    private let targetAppObserver: TargetAppObserver
    private var scrollMonitor: Any?
    private var underlineView: UnderlineView?

    // MARK: - Public state
    // internal(set) allows @testable test targets to inject state directly

    internal(set) var suggestions: [Suggestion] = []
    private(set) var textContext: TextContext?
    private(set) var isPopoverVisible: Bool = false
    private(set) var currentPopoverSuggestion: Suggestion?

    // MARK: - Action callbacks (wired by caller -- Plan 03 wires write-back)

    var onAcceptSuggestion: (@MainActor (Suggestion) -> Void)?
    var onDismissSuggestion: (@MainActor (Suggestion) -> Void)?
    var onAddToDictionary: (@MainActor (String) -> Void)?

    init(accessor: any AXAccessor = SystemAXAccessor()) {
        self.accessor = accessor
        self.overlayWindow = OverlayWindow()
        self.popoverPanel = SuggestionPopoverPanel()
        self.targetAppObserver = TargetAppObserver()

        // Wire key handler for Escape dismissal (D-13)
        overlayWindow.keyHandler = { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 { // Escape
                if self.isPopoverVisible {
                    self.closePopover()
                } else {
                    self.dismiss()
                }
            }
        }

        // Wire click-outside dismissal: mouseDown outside underlines triggers dismiss
        overlayWindow.mouseDownHandler = { [weak self] event in
            guard let self else { return }
            guard let view = self.underlineView else {
                self.dismiss()
                return
            }
            let localPoint = view.convert(event.locationInWindow, from: nil)
            if view.suggestionAt(point: localPoint) == nil {
                self.dismiss()
            }
        }
    }

    // MARK: - Bounds queries

    /// Converts a Suggestion's range to a CGRect in CG screen coordinates by querying
    /// the AX element for the glyph bounds. Returns nil on AX error or unpackable value.
    func boundsForRange(
        _ suggestion: Suggestion,
        in text: String,
        element: AXUIElement
    ) -> CGRect? {
        let cfRange = cfRangeFor(suggestion, in: text)
        var mutableRange = cfRange
        guard let axRangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        let (error, ref) = accessor.copyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute,
            axRangeValue
        )
        guard error == .success, let ref else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// Converts CG screen coordinates (y=0 at bottom) to AppKit window coordinates (y=0 at top).
    func flipCGRect(_ cgRect: CGRect, screenHeight: CGFloat) -> NSRect {
        NSRect(
            x: cgRect.origin.x,
            y: screenHeight - cgRect.origin.y - cgRect.height,
            width: cgRect.width,
            height: cgRect.height
        )
    }

    // MARK: - Display lifecycle

    /// Positions the overlay window and renders underlines for all suggestions.
    /// Silently skips suggestions whose AX bounds query returns nil (per UI-SPEC error state).
    /// Capped at maxDisplayedSuggestions to avoid blocking the main thread (T-03-02).
    func show(suggestions: [Suggestion], context: TextContext) {
        self.suggestions = Array(suggestions.prefix(Self.maxDisplayedSuggestions))
        self.textContext = context

        let screenHeight = NSScreen.main?.frame.height ?? 0
        let element = context.axElement

        var entries: [UnderlineEntry] = []
        for suggestion in self.suggestions {
            guard let cgRect = boundsForRange(suggestion, in: context.text, element: element) else {
                continue
            }
            let appKitRect = flipCGRect(cgRect, screenHeight: screenHeight)
            let underlineRect = NSRect(
                x: appKitRect.origin.x,
                y: appKitRect.origin.y,
                width: appKitRect.width,
                height: 2
            )
            let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
            entries.append(UnderlineEntry(
                underlineRect: underlineRect,
                hitRect: hitRect,
                suggestion: suggestion
            ))
        }

        guard !entries.isEmpty else { return }

        let unionRect = entries.reduce(CGRect.null) { $0.union($1.hitRect) }
        let padding: CGFloat = 4
        let windowRect = unionRect.insetBy(dx: -padding, dy: -padding)

        let view = UnderlineView()
        // Translate entry rects to window-local coordinates
        let localEntries = entries.map { entry in
            UnderlineEntry(
                underlineRect: entry.underlineRect.offsetBy(
                    dx: -windowRect.origin.x,
                    dy: -windowRect.origin.y
                ),
                hitRect: entry.hitRect.offsetBy(
                    dx: -windowRect.origin.x,
                    dy: -windowRect.origin.y
                ),
                suggestion: entry.suggestion
            )
        }
        view.entries = localEntries
        view.frame = NSRect(origin: .zero, size: windowRect.size)

        // Wire click-to-show-popover
        view.onClick = { [weak self] suggestion in
            self?.showPopover(for: suggestion)
        }

        underlineView = view
        overlayWindow.contentView = view
        overlayWindow.setFrame(windowRect, display: false)
        overlayWindow.orderFront(nil)

        // Install AX observer to dismiss on target app state changes
        let pid = NSRunningApplication.runningApplications(
            withBundleIdentifier: context.bundleID
        ).first?.processIdentifier
        if let pid {
            targetAppObserver.install(pid: pid) { [weak self] in
                self?.dismiss()
            }
        }

        // Start scroll monitor -- RESEARCH.md A2: does not require Input Monitoring TCC.
        // If assumption A2 is wrong, scroll dismissal silently fails. Verify manually on
        // a clean macOS account during the Plan 03 checkpoint.
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// Dismisses the overlay, closes any open popover, uninstalls the AX observer,
    /// and removes the scroll monitor.
    func dismiss() {
        closePopover()
        overlayWindow.orderOut(nil)
        overlayWindow.contentView = nil
        underlineView = nil
        suggestions = []
        textContext = nil
        targetAppObserver.uninstall()
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Popover management

    /// Shows the suggestion popover panel near the given suggestion's underline.
    /// Closes any previously open popover first (D-06: one at a time).
    func showPopover(for suggestion: Suggestion) {
        closePopover()

        let addToDictionaryCallback: (@MainActor @Sendable () -> Void)?
        if suggestion.category == .spelling {
            let word = suggestion.original
            addToDictionaryCallback = { [weak self] in self?.handleAddToDictionary(word: word) }
        } else {
            addToDictionaryCallback = nil
        }

        let popoverView = PopoverView(
            suggestion: suggestion,
            onAccept: { [weak self] in self?.handleAcceptSuggestion(suggestion) },
            onDismiss: { [weak self] in self?.handleDismissSuggestion(suggestion) },
            onAddToDictionary: addToDictionaryCallback
        )

        let hostingView = NSHostingView(rootView: popoverView)
        hostingView.sizingOptions = [.preferredContentSize]
        popoverPanel.setContent(hostingView)

        let screen = overlayWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let underlineRect = underlineRectForSuggestion(suggestion) ?? .zero
        popoverPanel.showNear(underlineRect: underlineRect, on: screen)

        currentPopoverSuggestion = suggestion
        isPopoverVisible = true
    }

    /// Closes the suggestion popover panel and clears popover state.
    func closePopover() {
        popoverPanel.orderOut(nil)
        currentPopoverSuggestion = nil
        isPopoverVisible = false
    }

    // MARK: - Suggestion action handlers (internal visibility for testing)

    func handleDismissSuggestion(_ suggestion: Suggestion) {
        closePopover()
        suggestions.removeAll { $0.id == suggestion.id }
        if let view = underlineView {
            view.entries.removeAll { $0.suggestion.id == suggestion.id }
            view.needsDisplay = true
        }
        onDismissSuggestion?(suggestion)
        if suggestions.isEmpty {
            dismiss()
        }
    }

    func handleAcceptSuggestion(_ suggestion: Suggestion) {
        onAcceptSuggestion?(suggestion)
        closePopover()
        // Plan 03 replaces this stub with full AX write-back + reposition logic.
    }

    func handleAddToDictionary(word: String) {
        onAddToDictionary?(word)
    }

    // MARK: - Private helpers

    private func cfRangeFor(_ suggestion: Suggestion, in text: String) -> CFRange {
        let scalars = text.unicodeScalars
        let location = scalars.distance(from: scalars.startIndex, to: suggestion.range.lowerBound)
        let length = scalars.distance(from: suggestion.range.lowerBound, to: suggestion.range.upperBound)
        return CFRange(location: location, length: length)
    }

    private func underlineRectForSuggestion(_ suggestion: Suggestion) -> NSRect? {
        underlineView?.entries.first { $0.suggestion.id == suggestion.id }?.underlineRect
    }
}
