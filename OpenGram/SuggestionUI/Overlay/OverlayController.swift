@preconcurrency import ApplicationServices
import AppKit
import os.log
import SwiftUI

/// Per-paragraph bundle used during rephrase-card dispatch. Internal visibility so
/// OverlayController.selectQualifier is unit-testable.
internal struct CardQualifier: Sendable {
    let paragraph: Paragraph
    let llmIssues: [LLMStyleSuggestion]
    let harperInside: [Suggestion]
    let hash: ParagraphHash
    /// Transitional UInt64 hash for the legacy `scheduler.markDismissed` call.
    /// Scheduler + this field are slated for deletion; `hash` becomes the sole identifier.
    let legacyHash: UInt64
}

/// Coordinates the overlay window and suggestion popover.
/// Owns the OverlayWindow, SuggestionPopoverPanel, TargetAppObserver, and scroll monitor.
@MainActor
final class OverlayController {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "OverlayController"
    )

    // T-03-02: cap displayed suggestions to prevent blocking the main thread with AX queries
    private static let maxDisplayedSuggestions = 50

    private let accessor: any AXAccessor
    private let scheduler: LLMCheckScheduler?
    private let textMonitor: TextMonitor?
    private let incrementalConfig: any IncrementalConfig
    private let splitter: any ParagraphSplitting
    private let hasher: any ParagraphHashing
    private let store: ParagraphSuggestionStore?
    private var storeSubscriptionTask: Task<Void, Never>?
    private let heuristic: DisplayHeuristic
    private let overlayWindow: OverlayWindow
    private let popoverPanel: SuggestionPopoverPanel
    private let targetAppObserver: TargetAppObserver
    private let rephraseCardPanelController: RephraseCardPanelController
    private let sourceParagraphHighlight: SourceParagraphHighlight
    private let boundsValidator = BoundsValidator()
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var underlineView: UnderlineView?
    private var targetAppPID: pid_t?
    private var currentCardParagraphRange: (scalarStart: Int, scalarLength: Int)?
    /// Hash of the paragraph currently shown in the rephrase card. Guards against re-dispatching
    /// the card for the same paragraph on incremental update() calls (WR-02).
    private var currentCardParagraphHash: ParagraphHash? = nil

    // MARK: - Public state

    var suggestions: [Suggestion] = []

    /// Parallel array of unicode scalar offsets for each suggestion in `suggestions`.
    /// Used to shift remaining suggestions after an accept changes text length.
    /// Index i in this array corresponds to index i in `suggestions`.
    var suggestionScalarOffsets: [(scalarStart: Int, scalarLength: Int)] = []

    var textContext: TextContext?

    /// D-13 / FR-19: while the rephrase card is visible for a paragraph, per-issue
    /// underlines for that paragraph are hidden. Stored as a scalar-offset range (NOT
    /// Range<String.Index> — research Pitfall #3) so it remains valid across text mutations.
    var hiddenParagraphScalarRange: (scalarStart: Int, scalarLength: Int)?

    private(set) var isPopoverVisible: Bool = false
    private(set) var currentPopoverSuggestion: Suggestion?
    private var currentAnimationState: PopoverAnimationState?
    private var popoverGeneration: UInt = 0

    // MARK: - Action callbacks (wired by caller)

    var onAcceptSuggestion: (@MainActor (Suggestion) -> Void)?
    var onDismissSuggestion: (@MainActor (Suggestion) -> Void)?
    var onAddToDictionary: (@MainActor (String) -> Void)?
    var onDismissAll: (@MainActor () -> Void)?

    init(
        accessor: any AXAccessor = SystemAXAccessor(),
        scheduler: LLMCheckScheduler? = nil,
        textMonitor: TextMonitor? = nil,
        incrementalConfig: any IncrementalConfig = UserDefaultsIncrementalConfig(),
        splitter: any ParagraphSplitting = DoubleNewlineSplitter(),
        hasher: any ParagraphHashing = Sha256ParagraphHasher(),
        store: ParagraphSuggestionStore? = nil
    ) {
        self.accessor = accessor
        self.scheduler = scheduler
        self.textMonitor = textMonitor
        self.incrementalConfig = incrementalConfig
        self.splitter = splitter
        self.hasher = hasher
        self.store = store
        self.heuristic = DisplayHeuristic(config: incrementalConfig)
        self.overlayWindow = OverlayWindow()
        self.popoverPanel = SuggestionPopoverPanel()
        self.targetAppObserver = TargetAppObserver()
        self.rephraseCardPanelController = RephraseCardPanelController()
        self.sourceParagraphHighlight = SourceParagraphHighlight(frame: .zero)

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

        if let store {
            self.storeSubscriptionTask = Task { @MainActor [weak self] in
                for await event in store.events {
                    guard let self else { return }
                    self.handleStoreEvent(event)
                }
            }
        }
    }

    deinit {
        storeSubscriptionTask?.cancel()
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

        // Card takes over presentation if a paragraph qualifies under flag-on.
        _ = tryDispatchRephraseCard(suggestions: self.suggestions, context: context)

        let element = context.axElement

        var entries: [UnderlineEntry] = []
        for (idx, suggestion) in self.suggestions.enumerated() {
            // D-13 / REPH-09: skip underlines inside the card's paragraph if any.
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

        // Wire click-to-show-popover.
        // PLL-02 / D-02: purple underline (source == .llm) routes to the rephrase card
        // rather than the word-level SuggestionPopoverPanel. The card is the sole popover
        // surface for paragraph rewrites.
        view.onClick = { [weak self] suggestion in
            guard let self else { return }
            if suggestion.source == .llm, let ctx = self.textContext {
                let paragraphLLM = self.suggestions.filter {
                    $0.source == .llm && $0.paragraphHash == suggestion.paragraphHash
                }
                _ = self.tryDispatchRephraseCard(
                    suggestions: paragraphLLM.isEmpty ? [suggestion] : paragraphLLM,
                    context: ctx
                )
            } else {
                self.showPopover(for: suggestion)
            }
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
            // D-13 / REPH-09: skip underlines inside the card's paragraph if any.
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
            // D-13 / REPH-09: skip underlines inside the card's paragraph if any.
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

        // Card takes over presentation if a paragraph qualifies under flag-on.
        _ = tryDispatchRephraseCard(suggestions: self.suggestions, context: newContext)

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

    // MARK: - Store subscription (D-04)

    @MainActor
    private func handleStoreEvent(_ event: StoreEvent) {
        guard case .suggestionsChanged(let bundleID) = event else { return }
        guard let ctx = textContext, ctx.bundleID == bundleID, let store else { return }
        Task { @MainActor [weak self] in
            guard let self, let store = self.store,
                  let ctx = self.textContext, ctx.bundleID == bundleID else { return }
            let rawLLM = await store.renderableSuggestions(for: bundleID)
            let liveResolved = self.resolveLLMRanges(rawLLM, in: ctx.text)
            let merged = self.mergeHarperAndLLM(ctx: ctx, newLLM: liveResolved)
            self.update(suggestions: merged, context: ctx)
        }
    }

    @MainActor
    private func resolveLLMRanges(_ llm: [Suggestion], in text: String) -> [Suggestion] {
        llm.compactMap { s in
            guard let live = text.range(of: s.original) else { return nil }
            return Suggestion(
                id: s.id,
                range: live,
                original: s.original,
                primaryReplacement: s.primaryReplacement,
                allReplacements: s.allReplacements,
                message: s.message,
                category: s.category,
                source: .llm,
                priority: s.priority,
                paragraphHash: s.paragraphHash
            )
        }
    }

    @MainActor
    private func mergeHarperAndLLM(ctx: TextContext, newLLM: [Suggestion]) -> [Suggestion] {
        let harper = self.suggestions.filter { $0.source == .harper }
        return harper + newLLM
    }

    // MARK: - Rephrase card dispatch (REPH-01/02/12/14/15)

    /// Entry point for card dispatch. Returns true when the card dispatched.
    /// Non-qualifying paragraphs continue through the caller's normal per-issue render path.
    @discardableResult
    private func tryDispatchRephraseCard(
        suggestions: [Suggestion],
        context: TextContext
    ) -> Bool {
        let llmCount = suggestions.filter { $0.source == .llm }.count
        let harperCount = suggestions.filter { $0.source == .harper }.count
        Self.logger.info("tryDispatchRephraseCard entry — suggestions=\(suggestions.count) llm=\(llmCount) harper=\(harperCount) bundleID=\(context.bundleID)")

        guard let scheduler, let textMonitor else {
            Self.logger.error("dispatch blocked: scheduler=\(self.scheduler != nil) textMonitor=\(self.textMonitor != nil) — one or both missing")
            return false
        }

        let paragraphs = splitter.split(context.text)
        guard !paragraphs.isEmpty else {
            Self.logger.info("dispatch blocked: splitter returned 0 paragraphs for text length \(context.text.count)")
            return false
        }
        Self.logger.info("split produced \(paragraphs.count) paragraph(s)")

        var qualifiers: [CardQualifier] = []
        for (idx, paragraph) in paragraphs.enumerated() {
            let hash = ParagraphHash(bundleID: context.bundleID, paragraphText: paragraph.text)
            let legacyHash = hasher.hash(paragraph.text)   // UInt64 — kept for scheduler.markDismissed only; slated for deletion

            let llmInRange = suggestions.filter { $0.source == .llm && $0.paragraphHash == hash }
            let llmIssues: [LLMStyleSuggestion] = llmInRange.compactMap { s in
                guard let revised = s.primaryReplacement else { return nil }
                let cat: LLMStyleSuggestion.Category
                switch s.category {
                case .clarity: cat = .clarity
                case .tone: cat = .tone
                case .rephrase: cat = .rephrase
                default: return nil
                }
                return LLMStyleSuggestion(
                    category: cat, originalText: s.original,
                    revisedText: revised, explanation: s.message,
                    confidence: Int(s.priority)
                )
            }

            let harperInside = suggestions.filter { s in
                s.source == .harper
                    && s.range.lowerBound >= paragraph.range.lowerBound
                    && s.range.upperBound <= paragraph.range.upperBound
            }

            let qualifies = heuristic.qualifies(paragraph: paragraph, issues: llmIssues)
            Self.logger.info("  paragraph[\(idx)] len=\(paragraph.text.count) hash=\(hash.sha256, privacy: .public) llmInRange=\(llmInRange.count) llmIssues=\(llmIssues.count) harperInside=\(harperInside.count) qualifies=\(qualifies)")

            if qualifies {
                qualifiers.append(CardQualifier(
                    paragraph: paragraph, llmIssues: llmIssues,
                    harperInside: harperInside, hash: hash, legacyHash: legacyHash
                ))
            }
        }
        guard !qualifiers.isEmpty else {
            Self.logger.info("dispatch blocked: 0 qualifying paragraphs (heuristic gate)")
            return false
        }
        Self.logger.info("\(qualifiers.count) qualifier(s) — selecting nearest to caret")

        let caretIndex = Self.caretScalarOffset(in: context.axElement)
        let selected = OverlayController.selectQualifier(
            qualifiers: qualifiers,
            caretScalarIndex: caretIndex,
            in: context.text
        )

        // WR-02: skip re-dispatch when the card is already showing for this paragraph.
        guard currentCardParagraphHash != selected.hash else {
            Self.logger.info("dispatch skipped: card already showing for paragraph hash=\(selected.hash.sha256, privacy: .public) (WR-02 dedup)")
            return true
        }

        var categoriesSet: Set<CheckCategory> = []
        for issue in selected.llmIssues {
            categoriesSet.insert(RephraseCardViewModel.checkCategory(from: issue.category))
        }
        for harper in selected.harperInside {
            categoriesSet.insert(harper.category)
        }
        let header = RephraseCardViewModel.headerText(for: categoriesSet)
        guard !header.isEmpty else {
            Self.logger.info("dispatch blocked: empty header (categories=\(categoriesSet.count))")
            return false
        }

        let rephrase = RephraseComposer.compose(
            paragraphText: selected.paragraph.text,
            issues: selected.llmIssues
        )
        let segments = TextDiff.segments(original: selected.paragraph.text, revised: rephrase)

        let scalars = context.text.unicodeScalars
        let pStart = scalars.distance(from: scalars.startIndex, to: selected.paragraph.range.lowerBound)
        let pLen = scalars.distance(from: selected.paragraph.range.lowerBound, to: selected.paragraph.range.upperBound)
        let paragraphScalarRange = (scalarStart: pStart, scalarLength: pLen)
        currentCardParagraphRange = paragraphScalarRange
        currentCardParagraphHash = selected.hash

        let schedulerRef = scheduler
        let bundleID = context.bundleID
        let hashForDismiss = selected.legacyHash     // UInt64 — legacy bridge, slated for deletion
        let ax = context.axElement
        let writeRange = paragraphScalarRange
        let composedRephrase = rephrase

        let acceptClosure: @MainActor () -> Void = { [weak self, storeRef = self.store] in
            guard let self else {
                OverlayController.logger.error("acceptClosure fired but self was released")
                return
            }
            OverlayController.logger.info("acceptClosure fired — replacement len=\(composedRephrase.count) writeRange=(\(writeRange.scalarStart), \(writeRange.scalarLength))")
            // PLL-11: store transition before AX write so eviction follows on next reconcile.
            if let storeRef { Task { await storeRef.markAccepted(hash: selected.hash) } }
            // Explicitly hide the panel before hideCardAndRestore() so the panel's onHide callback
            // is cleared before teardown — prevents double-fire of hideCardAndRestore() via the
            // kAXValueChangedNotification → handleKeystroke → hide() path (WR-04).
            self.rephraseCardPanelController.hide()
            self.hideCardAndRestore()
            let replacer = AXTextReplacer(accessor: self.accessor)
            let ok = replacer.replace(text: composedRephrase, in: writeRange, of: ax)
            OverlayController.logger.info("AXTextReplacer.replace returned \(ok)")
        }
        let dismissClosure: @MainActor () -> Void = { [weak self, storeRef = self.store] in
            guard let self else { return }
            Task { @MainActor in
                if let storeRef { await storeRef.markDismissed(hash: selected.hash) }
                // Legacy bridge — slated for deletion together with scheduler:
                await schedulerRef.markDismissed(bundleID: bundleID, hash: hashForDismiss)
                self.hideCardAndRestore()
            }
        }

        let viewModel = RephraseCardViewModel(
            paragraph: selected.paragraph,
            issues: selected.llmIssues,
            rephrase: rephrase,
            segments: segments,
            header: header,
            onAccept: acceptClosure,
            onDismiss: dismissClosure
        )

        guard let anchorRect = anchorRect(for: selected.paragraph, in: context) else {
            Self.logger.error("dispatch blocked: anchorRect computation failed for paragraph — AX bounds query may have returned nil")
            return false
        }
        Self.logger.info("anchorRect=\(NSStringFromRect(anchorRect)) for paragraph len=\(selected.paragraph.text.count)")
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorRect) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            Self.logger.error("dispatch blocked: no screen found for anchor + no fallback NSScreen available")
            return false
        }

        hideUnderlines(inParagraphScalarRange: paragraphScalarRange)
        showSourceHighlight(for: selected.paragraph, in: context)

        Self.logger.info("dispatch → RephraseCardPanelController.show (screen=\(NSStringFromRect(screen.visibleFrame)))")
        rephraseCardPanelController.show(
            viewModel: viewModel,
            near: anchorRect,
            on: screen,
            axElement: ax,
            paragraphScalarRange: paragraphScalarRange,
            textMonitor: textMonitor,
            onHide: { [weak self] in self?.hideCardAndRestore() }
        )
        return true
    }

    private func hideCardAndRestore() {
        sourceParagraphHighlight.removeFromSuperview()
        currentCardParagraphRange = nil
        currentCardParagraphHash = nil
        showUnderlines()
    }

    private func showSourceHighlight(for paragraph: Paragraph, in context: TextContext) {
        let fakeSug = Suggestion(
            id: UUID(), range: paragraph.range, original: paragraph.text,
            primaryReplacement: nil, allReplacements: [], message: "",
            category: .clarity, source: .llm, priority: 1, paragraphHash: nil
        )
        guard let rects = boundsValidator.validatedBoundsForRange(
            fakeSug, in: context.text, element: context.axElement,
            bundleID: context.bundleID, accessor: accessor
        ) else { return }
        let union = rects.reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return }

        let windowRect = overlayWindow.frame
        let localRect = NSRect(
            x: union.minX - windowRect.minX,
            y: union.minY - windowRect.minY,
            width: union.width,
            height: union.height
        )
        sourceParagraphHighlight.frame = localRect
        if let contentView = overlayWindow.contentView {
            contentView.addSubview(sourceParagraphHighlight, positioned: .below, relativeTo: underlineView)
        }
    }

    private func anchorRect(for paragraph: Paragraph, in context: TextContext) -> NSRect? {
        let fakeSug = Suggestion(
            id: UUID(), range: paragraph.range, original: paragraph.text,
            primaryReplacement: nil, allReplacements: [], message: "",
            category: .clarity, source: .llm, priority: 1, paragraphHash: nil
        )
        return boundsValidator.validatedBoundsForRange(
            fakeSug, in: context.text, element: context.axElement,
            bundleID: context.bundleID, accessor: accessor
        )?.first
    }

    private static func caretScalarOffset(in element: AXUIElement) -> Int? {
        var rangeRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)
        guard err == .success, let rangeRef else { return nil }
        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &cfRange) else { return nil }
        return cfRange.location
    }

    /// D-12 / REPH-12: caret-containment wins; otherwise nearest midpoint.
    /// Static + internal so unit tests can exercise without an OverlayController instance.
    internal static func selectQualifier(
        qualifiers: [CardQualifier],
        caretScalarIndex: Int?,
        in text: String
    ) -> CardQualifier {
        precondition(!qualifiers.isEmpty)
        guard let caret = caretScalarIndex else { return qualifiers[0] }

        let scalars = text.unicodeScalars
        func scalarRange(_ q: CardQualifier) -> (Int, Int) {
            let start = scalars.distance(from: scalars.startIndex, to: q.paragraph.range.lowerBound)
            let len = scalars.distance(from: q.paragraph.range.lowerBound, to: q.paragraph.range.upperBound)
            return (start, len)
        }
        for q in qualifiers {
            let (s, l) = scalarRange(q)
            if caret >= s && caret <= s + l { return q }
        }
        return qualifiers.min(by: { a, b in
            let (sa, la) = scalarRange(a)
            let (sb, lb) = scalarRange(b)
            let midA = sa + la / 2
            let midB = sb + lb / 2
            return abs(midA - caret) < abs(midB - caret)
        }) ?? qualifiers[0]
    }

    // MARK: - Paragraph underline hide/show (FR-19 / D-13)

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
