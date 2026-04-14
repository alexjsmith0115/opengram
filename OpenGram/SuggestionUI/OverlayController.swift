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
    private let boundsValidator = BoundsValidator()
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var underlineView: UnderlineView?
    private var targetAppPID: pid_t?

    // MARK: - Public state
    // internal(set) allows @testable test targets to inject state directly

    internal(set) var suggestions: [Suggestion] = []

    /// Parallel array of unicode scalar offsets for each suggestion in `suggestions`.
    /// Used to shift remaining suggestions after an accept changes text length.
    /// Index i in this array corresponds to index i in `suggestions`.
    internal(set) var suggestionScalarOffsets: [(scalarStart: Int, scalarLength: Int)] = []

    internal(set) var textContext: TextContext?
    private(set) var isPopoverVisible: Bool = false
    private(set) var currentPopoverSuggestion: Suggestion?
    private var currentAnimationState: PopoverAnimationState?
    private var popoverGeneration: UInt = 0

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

    // MARK: - Display lifecycle

    /// Positions the overlay window and renders underlines for all suggestions.
    /// Uses BoundsValidator for all bounds queries (supports multi-line, watchdog, app quirks).
    /// Silently skips suggestions whose bounds query returns nil.
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

        let element = context.axElement

        var entries: [UnderlineEntry] = []
        for suggestion in self.suggestions {
            guard let rects = boundsValidator.validatedBoundsForRange(
                suggestion, in: context.text, element: element,
                bundleID: context.bundleID, accessor: accessor
            ) else { continue }
            for rect in rects {
                let underlineRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: 2)
                let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
                entries.append(UnderlineEntry(underlineRect: underlineRect, hitRect: hitRect, suggestion: suggestion))
            }
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
            targetAppPID = pid
            targetAppObserver.install(pid: pid) { [weak self] in
                self?.dismiss()
            }
        }

        // Start scroll monitor filtered by target app PID (T-03-05).
        // RESEARCH.md A2: does not require Input Monitoring TCC.
        let targetPID = self.targetAppPID
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            if let targetPID,
               let cgEvent = event.cgEvent,
               cgEvent.getIntegerValueField(.eventTargetUnixProcessID) == Int64(targetPID) {
                self?.dismiss()
            }
        }

        // D-14: Only Escape remains as a global key monitor. Tab and Enter monitors removed.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 {
                self.handleEscape()
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
        targetAppPID = nil
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

        popoverGeneration &+= 1
        let animState = PopoverAnimationState()
        currentAnimationState = animState

        let popoverView = PopoverView(
            suggestion: suggestion,
            onAccept: { [weak self] in self?.handleAcceptSuggestion(suggestion) },
            onAcceptAlternative: { [weak self] alt in
                guard let self, let ctx = self.textContext else { return }
                self.acceptSuggestion(suggestion, context: ctx, replacementOverride: alt)
            },
            onDismiss: { [weak self] in self?.handleDismissSuggestion(suggestion) },
            onAddToDictionary: addToDictionaryCallback,
            animationState: animState
        )

        let hostingView = NSHostingView(rootView: popoverView)
        hostingView.sizingOptions = [.preferredContentSize]
        popoverPanel.setContent(hostingView)

        guard let screen = overlayWindow.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let localRect = underlineRectForSuggestion(suggestion) ?? .zero
        // Convert window-local coordinates back to screen coordinates for popover positioning
        let windowOrigin = overlayWindow.frame.origin
        let screenRect = localRect.offsetBy(dx: windowOrigin.x, dy: windowOrigin.y)
        popoverPanel.showNear(underlineRect: screenRect, on: screen)

        currentPopoverSuggestion = suggestion
        isPopoverVisible = true
    }

    /// Closes the suggestion popover panel with a D-17 reverse scale+fade animation.
    /// Triggers the dismiss animation, then removes the panel after 150ms.
    func closePopover() {
        guard isPopoverVisible else {
            currentPopoverSuggestion = nil
            return
        }
        isPopoverVisible = false
        currentPopoverSuggestion = nil

        // D-17: animate scale 100%→95% + fade out before removing the panel
        if let animState = currentAnimationState {
            withAnimation(.easeOut(duration: 0.15)) {
                animState.isVisible = false
            }
        }
        currentAnimationState = nil

        // Capture generation so the delayed orderOut is a no-op when a new popover opens
        let closingGeneration = popoverGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, self.popoverGeneration == closingGeneration else { return }
            self.popoverPanel.orderOut(nil)
        }
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

    /// Writes the suggestion's replacement to the target app.
    /// Primary path: range-targeted AX write (set selection + set selected text) per D-11.
    /// Fallback: full AXValue read/replace/write when range-targeted write is unavailable.
    /// After success: removes the accepted suggestion and repositions remaining underlines.
    /// Fails silently (suggestion stays) if AX write fails (T-03-07).
    /// `replacementOverride` substitutes an alternative replacement string (D-09 alternative accept).
    func acceptSuggestion(_ suggestion: Suggestion, context: TextContext, replacementOverride: String? = nil) {
        guard let replacement = replacementOverride ?? suggestion.primaryReplacement else { return }

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

        // Probe for range-targeted write capability (D-11, T-06-05)
        let (settableErr, isSettable) = accessor.isAttributeSettable(
            context.axElement, kAXSelectedTextRangeAttribute
        )
        let supportsRangeWrite = settableErr == .success && isSettable

        var writeSucceeded = false

        if supportsRangeWrite {
            var cfRange = CFRange(location: offset.scalarStart, length: offset.scalarLength)
            guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return }
            let selectError = accessor.setAttributeValue(
                context.axElement, kAXSelectedTextRangeAttribute, rangeValue
            )
            if selectError == .success {
                let replaceError = accessor.setAttributeValue(
                    context.axElement, kAXSelectedTextAttribute, replacement as CFString
                )
                if replaceError == .success {
                    writeSucceeded = true
                } else {
                    // Range set succeeded but text replace failed — fall through to full write
                    writeSucceeded = fallbackFullWrite(offset: offset, replacement: replacement, context: context)
                }
            } else {
                // Selection set failed — fall through to full write
                writeSucceeded = fallbackFullWrite(offset: offset, replacement: replacement, context: context)
            }
        } else {
            writeSucceeded = fallbackFullWrite(offset: offset, replacement: replacement, context: context)
        }

        guard writeSucceeded else { return }

        closePopover()
        onAcceptSuggestion?(suggestion)

        let replacementScalarCount = replacement.unicodeScalars.count
        suggestions.remove(at: offsetIndex)
        if offsetIndex < suggestionScalarOffsets.count {
            suggestionScalarOffsets.remove(at: offsetIndex)
        }

        if suggestions.isEmpty {
            dismiss()
            return
        }

        repositionAfterAccept(
            acceptedStart: offset.scalarStart,
            originalLength: offset.scalarLength,
            replacementLength: replacementScalarCount,
            context: context
        )
    }

    /// Full-text fallback: reads AXValue, replaces in-memory, writes back.
    /// Returns true on success, false on any AX error.
    @discardableResult
    private func fallbackFullWrite(
        offset: (scalarStart: Int, scalarLength: Int),
        replacement: String,
        context: TextContext
    ) -> Bool {
        let (readError, readRef) = accessor.copyAttributeValue(context.axElement, kAXValueAttribute)
        guard readError == .success, let currentText = readRef as? String else { return false }

        let scalars = currentText.unicodeScalars
        let startIdx = scalars.index(scalars.startIndex, offsetBy: offset.scalarStart)
        let endIdx = scalars.index(startIdx, offsetBy: offset.scalarLength)
        guard let stringStart = startIdx.samePosition(in: currentText) else { return false }
        guard let stringEnd = endIdx.samePosition(in: currentText) else { return false }

        var newText = currentText
        newText.replaceSubrange(stringStart..<stringEnd, with: replacement)

        let writeError = accessor.setAttributeValue(
            context.axElement,
            kAXValueAttribute,
            newText as CFString
        )
        return writeError == .success
    }

    /// Shifts scalar offsets for all remaining suggestions that start after the accepted range,
    /// re-reads the updated element text, and redraws underlines using BoundsValidator.
    /// Drops suggestions whose bounds re-query returns nil (D-12).
    /// Calls dismiss() if all re-queries fail (D-12).
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
            dismiss()
            return
        }

        // Shift offsets for suggestions after the accepted range; zero out overlapping ones.
        for i in 0..<suggestionScalarOffsets.count {
            let off = suggestionScalarOffsets[i]
            let overlapStart = max(off.scalarStart, acceptedStart)
            let overlapEnd = min(off.scalarStart + off.scalarLength, acceptedStart + originalLength)
            if overlapStart < overlapEnd {
                suggestionScalarOffsets[i] = (scalarStart: off.scalarStart, scalarLength: 0)
                continue
            }
            if off.scalarStart >= acceptedStart + originalLength {
                suggestionScalarOffsets[i] = (
                    scalarStart: off.scalarStart + delta,
                    scalarLength: off.scalarLength
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

        // Rebuild underline entries using BoundsValidator — drop suggestions whose re-query fails (D-12).
        // Survivor computation always runs to keep suggestions consistent with reality.
        guard suggestionScalarOffsets.count == suggestions.count else { return }

        var newEntries: [UnderlineEntry] = []
        var survivingSuggestions: [Suggestion] = []
        var survivingOffsets: [(scalarStart: Int, scalarLength: Int)] = []
        let windowOrigin = overlayWindow.frame.origin

        for (i, suggestion) in suggestions.enumerated() {
            guard let rects = boundsValidator.validatedBoundsForRange(
                suggestion, in: newText, element: context.axElement,
                bundleID: context.bundleID, accessor: accessor
            ) else { continue }

            survivingSuggestions.append(suggestion)
            survivingOffsets.append(suggestionScalarOffsets[i])

            for rect in rects {
                let underlineRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: 2)
                let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
                newEntries.append(UnderlineEntry(
                    underlineRect: underlineRect.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y),
                    hitRect: hitRect.offsetBy(dx: -windowOrigin.x, dy: -windowOrigin.y),
                    suggestion: suggestion
                ))
            }
        }

        suggestions = survivingSuggestions
        suggestionScalarOffsets = survivingOffsets

        if newEntries.isEmpty {
            dismiss()
            return
        }

        if let view = underlineView {
            view.entries = newEntries
            view.needsDisplay = true
        }
    }

    // MARK: - Keyboard Navigation

    /// Closes the popover if open, or dismisses the full overlay if no popover is open.
    /// D-15: Escape is the only retained key monitor action.
    func handleEscape() {
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

    private func underlineRectForSuggestion(_ suggestion: Suggestion) -> NSRect? {
        underlineView?.entries.first { $0.suggestion.id == suggestion.id }?.underlineRect
    }
}
