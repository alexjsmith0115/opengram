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

    /// Phase 18 D-13 / FR-19: while the rephrase card is visible for a paragraph, per-issue
    /// underlines for that paragraph are hidden. Stored as a scalar-offset range (NOT
    /// Range<String.Index> — research Pitfall #3) so it remains valid across text mutations.
    internal(set) var hiddenParagraphScalarRange: (scalarStart: Int, scalarLength: Int)?

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
        self.suggestionScalarOffsets = computeScalarOffsets(for: self.suggestions, in: context.text)

        let element = context.axElement

        var entries: [UnderlineEntry] = []
        for (idx, suggestion) in self.suggestions.enumerated() {
            // Phase 18 D-13 / REPH-09: skip underlines inside the card's paragraph if any.
            let off = self.suggestionScalarOffsets[idx]
            if shouldHideUnderline(scalarStart: off.scalarStart, scalarLength: off.scalarLength) { continue }
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
        let localEntries = Self.toLocalEntries(entries, in: windowRect)
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

        // Dismiss on any scroll: cgEvent is often nil for native Cocoa scroll events,
        // making PID-filtered dismissal unreliable. Any scroll while visible means
        // underline positions are stale, so unconditional dismiss is correct.
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] _ in
            self?.dismiss()
        }

        // D-14: Only Escape remains as a global key monitor. Tab and Enter monitors removed.
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if event.keyCode == 53 {
                self.handleEscape()
            }
        }
    }

    /// Updates the overlay using a diff-merge strategy to avoid tearing down and
    /// rebuilding the window when only a subset of suggestions has changed (D-12).
    ///
    /// Falls through to `show()` when:
    /// - The overlay window is not currently visible (first display).
    /// - The context has a different bundleID (user moved to a different field/app).
    ///
    /// Calls `dismiss()` when `newSuggestions` is empty (all errors resolved).
    func update(suggestions newSuggestions: [Suggestion], context newContext: TextContext) {
        // Fall through to show() for first display or when overlay is not visible
        guard overlayWindow.isVisible, textContext != nil else {
            show(suggestions: newSuggestions, context: newContext)
            return
        }

        // Field changed — tear down and rebuild cleanly
        if textContext?.bundleID != newContext.bundleID {
            show(suggestions: newSuggestions, context: newContext)
            return
        }

        if newSuggestions.isEmpty {
            dismiss()
            return
        }

        let cappedNew = Array(newSuggestions.prefix(Self.maxDisplayedSuggestions))
        let newOffsets = computeScalarOffsets(for: cappedNew, in: newContext.text)

        let diff = SuggestionDiffEngine.diff(
            old: self.suggestions,
            oldOffsets: self.suggestionScalarOffsets,
            new: cappedNew,
            newOffsets: newOffsets
        )

        // No visual change needed — just refresh the context timestamp
        if diff.added.isEmpty && diff.removed.isEmpty {
            self.textContext = newContext
            return
        }

        // Build surviving arrays: unchanged entries keep existing underline positions,
        // added entries get fresh bounds queries (T-07-07: only query AX for new suggestions).
        var survivingSuggestions: [Suggestion] = []
        var survivingOffsets: [(scalarStart: Int, scalarLength: Int)] = []
        var survivingEntries: [UnderlineEntry] = []

        let existingEntries = underlineView?.entries ?? []

        for (oldIndex, newIndex) in diff.unchanged {
            let off = newOffsets[newIndex]
            // Phase 18 D-13 / REPH-09: skip underlines inside the card's paragraph if any.
            if shouldHideUnderline(scalarStart: off.scalarStart, scalarLength: off.scalarLength) {
                survivingSuggestions.append(cappedNew[newIndex])
                survivingOffsets.append(off)
                continue
            }
            survivingSuggestions.append(cappedNew[newIndex])
            survivingOffsets.append(off)
            let oldSuggestion = self.suggestions[oldIndex]
            let kept = existingEntries.filter { $0.suggestion.id == oldSuggestion.id }
            survivingEntries.append(contentsOf: kept)
        }

        let element = newContext.axElement
        for newIndex in diff.added {
            let suggestion = cappedNew[newIndex]
            let off = newOffsets[newIndex]
            // Phase 18 D-13 / REPH-09: skip underlines inside the card's paragraph if any.
            if shouldHideUnderline(scalarStart: off.scalarStart, scalarLength: off.scalarLength) {
                survivingSuggestions.append(suggestion)
                survivingOffsets.append(off)
                continue
            }
            guard let rects = boundsValidator.validatedBoundsForRange(
                suggestion, in: newContext.text, element: element,
                bundleID: newContext.bundleID, accessor: accessor
            ) else { continue }
            survivingSuggestions.append(suggestion)
            survivingOffsets.append(off)
            for rect in rects {
                let underlineRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: 2)
                let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
                survivingEntries.append(UnderlineEntry(underlineRect: underlineRect, hitRect: hitRect, suggestion: suggestion))
            }
        }

        // Close popover if its suggestion was removed
        if let popoverSuggestion = currentPopoverSuggestion {
            let removedIDs = Set(diff.removed.map { self.suggestions[$0].id })
            if removedIDs.contains(popoverSuggestion.id) {
                closePopover()
            }
        }

        self.suggestions = survivingSuggestions
        self.suggestionScalarOffsets = survivingOffsets
        self.textContext = newContext

        if survivingEntries.isEmpty {
            dismiss()
            return
        }

        // Translate entries to window-local coordinates and update the view
        let unionRect = survivingEntries.reduce(CGRect.null) { $0.union($1.hitRect) }
        let padding: CGFloat = 4
        let windowRect = unionRect.insetBy(dx: -padding, dy: -padding)

        let localEntries = Self.toLocalEntries(survivingEntries, in: windowRect)

        if let view = underlineView {
            view.entries = localEntries
            view.frame = NSRect(origin: .zero, size: windowRect.size)
            view.needsDisplay = true
        }
        overlayWindow.setFrame(windowRect, display: false)
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

    // MARK: - Paragraph underline hide/show (Phase 18 FR-19 / D-13)

    /// Hides all per-issue underlines whose scalar offset overlaps `range`. The card is the
    /// sole interaction surface for the target paragraph while visible (REPH-09 / FR-19).
    /// Call `showUnderlines()` to restore.
    func hideUnderlines(inParagraphScalarRange range: (scalarStart: Int, scalarLength: Int)) {
        hiddenParagraphScalarRange = range
        applyHiddenFilterToCurrentEntries()
    }

    /// Clears the hidden-paragraph filter and restores all underlines for the current suggestions.
    func showUnderlines() {
        hiddenParagraphScalarRange = nil
        rebuildUnderlineEntriesFromSuggestions()
    }

    /// Tests whether a scalar offset should be hidden under the current filter.
    internal func shouldHideUnderline(scalarStart: Int, scalarLength: Int) -> Bool {
        guard let r = hiddenParagraphScalarRange else { return false }
        let aEnd = scalarStart + scalarLength
        let bEnd = r.scalarStart + r.scalarLength
        return scalarStart < bEnd && aEnd > r.scalarStart
    }

    /// Re-filters the existing underlineView.entries in-place using the current hidden range.
    /// Does not re-query AX — positions of surviving entries are kept as-is.
    private func applyHiddenFilterToCurrentEntries() {
        guard let view = underlineView else { return }
        var offsetByID: [UUID: (Int, Int)] = [:]
        for (i, s) in suggestions.enumerated() where i < suggestionScalarOffsets.count {
            offsetByID[s.id] = (suggestionScalarOffsets[i].scalarStart, suggestionScalarOffsets[i].scalarLength)
        }
        view.entries = view.entries.filter { entry in
            guard let (ss, sl) = offsetByID[entry.suggestion.id] else { return true }
            return !shouldHideUnderline(scalarStart: ss, scalarLength: sl)
        }
        view.needsDisplay = true
    }

    /// Rebuilds underline entries from the current suggestion list, bypassing the hidden filter.
    /// Falls back to no-op if context is absent.
    private func rebuildUnderlineEntriesFromSuggestions() {
        guard let ctx = textContext, let view = underlineView else { return }
        var entries: [UnderlineEntry] = []
        for suggestion in suggestions {
            guard let rects = boundsValidator.validatedBoundsForRange(
                suggestion, in: ctx.text, element: ctx.axElement,
                bundleID: ctx.bundleID, accessor: accessor
            ) else { continue }
            for rect in rects {
                let underlineRect = NSRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: 2)
                let hitRect = UnderlineView.expandedHitRect(from: underlineRect)
                entries.append(UnderlineEntry(underlineRect: underlineRect, hitRect: hitRect, suggestion: suggestion))
            }
        }
        let windowRect = overlayWindow.frame
        let localEntries = Self.toLocalEntries(entries, in: windowRect)
        view.entries = localEntries
        view.needsDisplay = true
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

        let replacer = AXTextReplacer(accessor: accessor)
        let writeSucceeded = replacer.replace(
            text: replacement,
            in: (scalarStart: offset.scalarStart, scalarLength: offset.scalarLength),
            of: context.axElement
        )

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

        // Rebuild suggestions with ranges pointing into the new text.
        // cfRangeFor() computes AX bounds positions from suggestion.range, which are
        // String.Index values bound to the OLD text. Without this rebuild, the AX query
        // asks for bounds at stale character positions.
        var rebuiltSuggestions: [Suggestion] = []
        var rebuiltOffsets: [(scalarStart: Int, scalarLength: Int)] = []
        for (i, suggestion) in suggestions.enumerated() {
            let off = suggestionScalarOffsets[i]
            guard off.scalarLength > 0,
                  let newRange = newText.rangeFromCharOffsets(
                      start: off.scalarStart, end: off.scalarStart + off.scalarLength)
            else { continue }
            rebuiltSuggestions.append(Suggestion(
                id: suggestion.id,
                range: newRange,
                original: suggestion.original,
                primaryReplacement: suggestion.primaryReplacement,
                allReplacements: suggestion.allReplacements,
                message: suggestion.message,
                category: suggestion.category,
                source: suggestion.source,
                priority: suggestion.priority,
                paragraphHash: suggestion.paragraphHash
            ))
            rebuiltOffsets.append(off)
        }
        suggestions = rebuiltSuggestions
        suggestionScalarOffsets = rebuiltOffsets

        // Rebuild underline entries using BoundsValidator — drop suggestions whose re-query fails (D-12).
        // Survivor computation always runs to keep suggestions consistent with reality.
        guard suggestionScalarOffsets.count == suggestions.count else { return }

        // Build entries in screen coordinates first so we can compute the new window frame.
        var screenEntries: [UnderlineEntry] = []
        var survivingSuggestions: [Suggestion] = []
        var survivingOffsets: [(scalarStart: Int, scalarLength: Int)] = []

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
                screenEntries.append(UnderlineEntry(underlineRect: underlineRect, hitRect: hitRect, suggestion: suggestion))
            }
        }

        suggestions = survivingSuggestions
        suggestionScalarOffsets = survivingOffsets

        if screenEntries.isEmpty {
            dismiss()
            return
        }

        // Recalculate window frame from new screen-coord entry union (mirrors show() pattern).
        let unionRect = screenEntries.reduce(CGRect.null) { $0.union($1.hitRect) }
        let padding: CGFloat = 4
        let newWindowRect = unionRect.insetBy(dx: -padding, dy: -padding)

        let localEntries = Self.toLocalEntries(screenEntries, in: newWindowRect)

        if let view = underlineView {
            view.entries = localEntries
            view.frame = NSRect(origin: .zero, size: newWindowRect.size)
            view.needsDisplay = true
        }
        overlayWindow.setFrame(newWindowRect, display: false)
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

    /// Translates screen-coordinate entries to window-local coordinates.
    private static func toLocalEntries(_ entries: [UnderlineEntry], in windowRect: NSRect) -> [UnderlineEntry] {
        entries.map { entry in
            UnderlineEntry(
                underlineRect: entry.underlineRect.offsetBy(dx: -windowRect.origin.x, dy: -windowRect.origin.y),
                hitRect: entry.hitRect.offsetBy(dx: -windowRect.origin.x, dy: -windowRect.origin.y),
                suggestion: entry.suggestion
            )
        }
    }

    /// Computes parallel unicode scalar offsets for a suggestion array relative to the given text.
    private func computeScalarOffsets(
        for suggestions: [Suggestion],
        in text: String
    ) -> [(scalarStart: Int, scalarLength: Int)] {
        let scalars = text.unicodeScalars
        return suggestions.map { s in
            let start = scalars.distance(from: scalars.startIndex, to: s.range.lowerBound)
            let length = scalars.distance(from: s.range.lowerBound, to: s.range.upperBound)
            return (scalarStart: start, scalarLength: length)
        }
    }
}
