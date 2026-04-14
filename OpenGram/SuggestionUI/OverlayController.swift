@preconcurrency import ApplicationServices
import AppKit
import SwiftUI

/// Coordinates the overlay window and suggestion popover.
/// Owns the OverlayWindow, SuggestionPopoverPanel, TargetAppObserver, and scroll monitor.
@MainActor
final class OverlayController {

    // T-03-02: cap displayed suggestions to prevent blocking the main thread with AX queries
    private static let maxDisplayedSuggestions = 50

    private let accessor: any AXAccessor
    private let overlayWindow: OverlayWindow
    private let popoverPanel: SuggestionPopoverPanel
    private let targetAppObserver: TargetAppObserver
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var underlineView: UnderlineView?

    // MARK: - Public state
    // internal(set) allows @testable test targets to inject state directly

    internal(set) var suggestions: [Suggestion] = []

    /// Parallel array of unicode scalar offsets for each suggestion in `suggestions`.
    /// Used to shift remaining suggestions after an accept changes text length.
    /// Index i in this array corresponds to index i in `suggestions`.
    var suggestionScalarOffsets: [(scalarStart: Int, scalarLength: Int)] = []

    internal(set) var textContext: TextContext?
    private(set) var isPopoverVisible: Bool = false
    private(set) var currentPopoverSuggestion: Suggestion?

    // MARK: - Action callbacks (wired by caller)

    var onAcceptSuggestion: (@MainActor (Suggestion) -> Void)?
    var onDismissSuggestion: (@MainActor (Suggestion) -> Void)?
    var onAddToDictionary: (@MainActor (String) -> Void)?
    var onDismissAll: (@MainActor () -> Void)?

    init(accessor: any AXAccessor = SystemAXAccessor()) {
        self.accessor = accessor
        self.overlayWindow = OverlayWindow()
        self.popoverPanel = SuggestionPopoverPanel()
        self.targetAppObserver = TargetAppObserver()

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

        // Populate parallel scalar offset array so repositionAfterAccept can shift indices
        let scalars = context.text.unicodeScalars
        self.suggestionScalarOffsets = self.suggestions.map { s in
            let start = scalars.distance(from: scalars.startIndex, to: s.range.lowerBound)
            let length = scalars.distance(from: s.range.lowerBound, to: s.range.upperBound)
            return (scalarStart: start, scalarLength: length)
        }

        let screenHeight = NSScreen.main?.frame.height ?? 0
        let element = context.axElement

        var entries: [UnderlineEntry] = []
        for suggestion in self.suggestions {
            guard let cgRect = boundsForRange(suggestion, in: context.text, element: element) else {
                continue
            }
            // Sanity clamp: some apps (e.g., Notes title line) return the full line width
            // for short ranges. If width-per-char exceeds line height, clamp to an estimate.
            var clampedRect = cgRect
            let charCount = max(CGFloat(suggestion.original.count), 1)
            if clampedRect.width > clampedRect.height * charCount {
                clampedRect.size.width = clampedRect.height * 0.7 * charCount
            }
            let appKitRect = flipCGRect(clampedRect, screenHeight: screenHeight)
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

        // D-14: Only Escape remains as a global key monitor. Tab and Enter monitors removed.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 {
                self.handleEscape(textContext: self.textContext)
            }
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
        suggestionScalarOffsets = []
        textContext = nil
        targetAppObserver.uninstall()
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        onDismissAll?()
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
        let localRect = underlineRectForSuggestion(suggestion) ?? .zero
        // Convert window-local coordinates back to screen coordinates for popover positioning
        let windowOrigin = overlayWindow.frame.origin
        let screenRect = localRect.offsetBy(dx: windowOrigin.x, dy: windowOrigin.y)
        popoverPanel.showNear(underlineRect: screenRect, on: screen)

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
        guard let context = textContext else { return }
        acceptSuggestion(suggestion, context: context)
    }

    // MARK: - Accept / Write-back

    /// Writes the suggestion's primary replacement to the target app via AX set-range-then-replace,
    /// then removes the accepted suggestion and repositions remaining underlines.
    /// Fails silently (suggestion stays) if any AX call returns a non-success error (T-03-07).
    func acceptSuggestion(_ suggestion: Suggestion, context: TextContext) {
        guard let replacement = suggestion.primaryReplacement else { return }

        // Locate this suggestion in the array
        guard let offsetIndex = suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }

        // Ensure the parallel offset array is populated (may be missing if show() wasn't called)
        if suggestionScalarOffsets.count != suggestions.count {
            let scalars = context.text.unicodeScalars
            suggestionScalarOffsets = suggestions.map { s in
                let start = scalars.distance(from: scalars.startIndex, to: s.range.lowerBound)
                let length = scalars.distance(from: s.range.lowerBound, to: s.range.upperBound)
                return (scalarStart: start, scalarLength: length)
            }
        }

        let offset = suggestionScalarOffsets[offsetIndex]

        // Read the current full text from the target element
        let (readError, readRef) = accessor.copyAttributeValue(context.axElement, kAXValueAttribute)
        guard readError == .success, let currentText = readRef as? String else { return }

        // Perform the replacement in-memory using scalar offsets
        let scalars = currentText.unicodeScalars
        let startIdx = scalars.index(scalars.startIndex, offsetBy: offset.scalarStart)
        let endIdx = scalars.index(startIdx, offsetBy: offset.scalarLength)
        let stringStart = startIdx.samePosition(in: currentText) ?? String.Index(startIdx, within: currentText)!
        let stringEnd = endIdx.samePosition(in: currentText) ?? String.Index(endIdx, within: currentText)!

        var newText = currentText
        newText.replaceSubrange(stringStart..<stringEnd, with: replacement)

        // Write the full modified text back
        let writeError = accessor.setAttributeValue(
            context.axElement,
            kAXValueAttribute,
            newText as CFString
        )
        guard writeError == .success else { return }

        // 3. Close popover
        closePopover()

        // 4. Notify caller before removing from array
        onAcceptSuggestion?(suggestion)

        // 5. Remove accepted suggestion and its offset entry
        let replacementScalarCount = replacement.unicodeScalars.count
        suggestions.remove(at: offsetIndex)
        if offsetIndex < suggestionScalarOffsets.count {
            suggestionScalarOffsets.remove(at: offsetIndex)
        }

        // 6. If no suggestions remain, dismiss overlay
        if suggestions.isEmpty {
            dismiss()
            return
        }

        // 7. Reposition remaining suggestions by shifting scalar offsets
        repositionAfterAccept(
            acceptedStart: offset.scalarStart,
            originalLength: offset.scalarLength,
            replacementLength: replacementScalarCount,
            context: context
        )
    }

    /// Shifts scalar offsets for all remaining suggestions that start after the accepted range,
    /// re-reads the updated element text, and redraws underlines with fresh AX bounds.
    private func repositionAfterAccept(
        acceptedStart: Int,
        originalLength: Int,
        replacementLength: Int,
        context: TextContext
    ) {
        let delta = replacementLength - originalLength

        // Re-read current text so we have valid content for bounds re-queries
        let (valError, valRef) = accessor.copyAttributeValue(context.axElement, kAXValueAttribute)
        guard valError == .success, let newText = valRef as? String else {
            // Can't re-read — positions are now unreliable, dismiss
            dismiss()
            return
        }

        // Shift offsets for suggestions starting after the accepted range
        for i in 0..<suggestionScalarOffsets.count {
            if suggestionScalarOffsets[i].scalarStart >= acceptedStart + originalLength {
                suggestionScalarOffsets[i] = (
                    scalarStart: suggestionScalarOffsets[i].scalarStart + delta,
                    scalarLength: suggestionScalarOffsets[i].scalarLength
                )
            }
        }

        // Update stored text context with new text
        textContext = TextContext(
            text: newText,
            bundleID: context.bundleID,
            extractionMethod: context.extractionMethod,
            selectionRange: context.selectionRange,
            elementBounds: context.elementBounds,
            axElement: context.axElement
        )

        // Rebuild underline entries using shifted offsets and new AX bounds
        guard let view = underlineView,
              suggestionScalarOffsets.count == suggestions.count else { return }
        let screenHeight = NSScreen.main?.frame.height ?? 0

        var newEntries: [UnderlineEntry] = []
        for (i, suggestion) in suggestions.enumerated() {
            let scalarOffset = suggestionScalarOffsets[i]
            // Re-build a CFRange from shifted scalar offset
            var cfRange = CFRange(location: scalarOffset.scalarStart, length: scalarOffset.scalarLength)
            guard let axRangeValue = AXValueCreate(.cfRange, &cfRange) else { continue }

            let (boundsError, boundsRef) = accessor.copyParameterizedAttributeValue(
                context.axElement,
                kAXBoundsForRangeParameterizedAttribute,
                axRangeValue
            )
            guard boundsError == .success, let boundsRef else { continue }
            var cgRect = CGRect.zero
            guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &cgRect) else { continue }

            let appKitRect = flipCGRect(cgRect, screenHeight: screenHeight)
            let underlineRect = NSRect(
                x: appKitRect.origin.x,
                y: appKitRect.origin.y,
                width: appKitRect.width,
                height: 2
            )
            let hitRect = UnderlineView.expandedHitRect(from: underlineRect)

            // Translate to window-local coordinates
            let windowOrigin = overlayWindow.frame.origin
            newEntries.append(UnderlineEntry(
                underlineRect: underlineRect.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y),
                hitRect: hitRect.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y),
                suggestion: suggestion
            ))
        }

        view.entries = newEntries
        view.needsDisplay = true
    }

    // MARK: - Keyboard Navigation

    /// Closes the popover if open, or dismisses the full overlay if no popover is open.
    func handleEscape(textContext: TextContext?) {
        if isPopoverVisible {
            closePopover()
        } else {
            dismiss()
        }
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
