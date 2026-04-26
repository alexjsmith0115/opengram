import Testing
import AppKit
@preconcurrency import ApplicationServices

@testable import OpenGramLib

// MARK: - Helpers

private func makeDiffSuggestion(
    in text: String,
    scalarStart: Int,
    scalarLength: Int,
    original: String,
    primaryReplacement: String = "fixed",
    category: CheckCategory = .spelling,
    source: SuggestionSource = .harper
) -> Suggestion {
    let scalars = text.unicodeScalars
    let lower = scalars.index(scalars.startIndex, offsetBy: scalarStart)
    let upper = scalars.index(lower, offsetBy: scalarLength)
    let range = lower..<upper
    return Suggestion(
        id: UUID(),
        range: range,
        original: original,
        primaryReplacement: primaryReplacement,
        allReplacements: [primaryReplacement],
        message: "Spelling error.",
        category: category,
        source: source,
        priority: 5,
        paragraphHash: nil
    )
}

private func makeContext(text: String) -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.apple.TextEdit",
        extractionMethod: .axDirectSelection,
        selectionRange: nil,
        elementBounds: nil,
        axElement: AXUIElementCreateSystemWide()
    )
}

private func makeAccessorWithRect(
    _ rect: CGRect = CGRect(x: 100, y: 200, width: 50, height: 14)
) -> MockAXAccessor {
    let accessor = MockAXAccessor()
    var r = rect
    let axValue = AXValueCreate(.cgRect, &r)!
    accessor.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, axValue)
    return accessor
}

@MainActor
private func makeDiffMonitor() -> TextMonitor {
    TextMonitor(
        textEngine: TMockAXTextEngine(),
        orchestrator: CheckOrchestrator(harper: TMockGrammarChecker()),
        capabilityCache: TMockCapabilityCache()
    )
}

// MARK: - OverlayController Diff Tests

@Suite("OverlayController diff-merge update()")
@MainActor
struct OverlayControllerDiffTests {

    // Test 1: identical suggestion set produces no underline changes (no flicker)
    @Test("update with identical suggestions does not change suggestion count")
    func updateIdenticalSuggestionsNoFlicker() throws {
        let text = "Ths is a tset sentense."
        let accessor = makeAccessorWithRect()
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)

        let s1 = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let s2 = makeDiffSuggestion(in: text, scalarStart: 9, scalarLength: 4, original: "tset")

        controller.show(suggestions: [s1, s2], context: context)
        #expect(controller.suggestions.count == 2)

        // Same suggestions again — update should keep the same count
        let s1b = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let s2b = makeDiffSuggestion(in: text, scalarStart: 9, scalarLength: 4, original: "tset")

        controller.update(suggestions: [s1b, s2b], context: context)

        #expect(controller.suggestions.count == 2)
    }

    // Test 2: one new suggestion added without rebuilding existing ones
    @Test("update with new suggestion adds it to the set")
    func updateAddsNewSuggestion() throws {
        let text = "Ths is a tset sentense."
        let accessor = makeAccessorWithRect()
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)

        let s1 = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        controller.show(suggestions: [s1], context: context)
        #expect(controller.suggestions.count == 1)

        // Add a second suggestion
        let s1b = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let s2 = makeDiffSuggestion(in: text, scalarStart: 9, scalarLength: 4, original: "tset")

        controller.update(suggestions: [s1b, s2], context: context)

        #expect(controller.suggestions.count == 2)
        #expect(controller.suggestions.contains(where: { $0.original == "tset" }))
    }

    // Test 3: one removed suggestion is dropped, rest remain
    @Test("update with removed suggestion removes it from the set")
    func updateRemovesSuggestion() throws {
        let text = "Ths is a tset sentense."
        let accessor = makeAccessorWithRect()
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)

        let s1 = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let s2 = makeDiffSuggestion(in: text, scalarStart: 9, scalarLength: 4, original: "tset")

        controller.show(suggestions: [s1, s2], context: context)
        #expect(controller.suggestions.count == 2)

        // Remove s1 (user fixed "Ths")
        let newText = "This is a tset sentense."
        let s2b = makeDiffSuggestion(in: newText, scalarStart: 10, scalarLength: 4, original: "tset")
        let newContext = makeContext(text: newText)

        controller.update(suggestions: [s2b], context: newContext)

        #expect(controller.suggestions.count == 1)
        #expect(controller.suggestions.contains(where: { $0.original == "tset" }))
        #expect(!controller.suggestions.contains(where: { $0.original == "Ths" }))
    }

    // Test 4: when overlay is not visible, update falls through to show()
    @Test("update when overlay not visible falls through to show()")
    func updateWhenNotVisibleCallsShow() throws {
        let text = "Ths is a tset."
        let accessor = makeAccessorWithRect()
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)

        let s1 = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")

        // Do NOT call show() first — overlay is not visible
        controller.update(suggestions: [s1], context: context)

        // After update falling through to show(), suggestions should be populated
        #expect(controller.suggestions.count == 1)
    }

    @Test("show includes room for the animated hover highlight")
    func showIncludesHoverHighlightFrame() throws {
        let text = "Ths is a tset."
        let accessor = makeAccessorWithRect(CGRect(x: 100, y: 200, width: 80, height: 18))
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)
        let suggestion = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")

        controller.show(suggestions: [suggestion], context: context)

        #expect(controller.overlayWindow.frame.height <= 28)
        #expect(controller.underlineView?.entries.first?.highlightRect.height == 18)
    }

    @Test("global mouse down detects clicks over underline hit band")
    func globalMouseDownDetectsUnderlineHitBand() throws {
        let text = "Ths is a tset."
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let view = UnderlineView()
        view.entries = [
            UnderlineEntry(
                underlineRect: NSRect(x: 10, y: 10, width: 80, height: 2),
                hitRect: UnderlineView.expandedHitRect(from: NSRect(x: 10, y: 10, width: 80, height: 2)),
                suggestion: suggestion
            )
        ]
        controller.underlineView = view
        controller.overlayWindow.setFrame(NSRect(x: 100, y: 200, width: 120, height: 80), display: false)

        let handled = controller.handleGlobalMouseDown(screenPoint: NSPoint(x: 120, y: 211))
        #expect(handled == true)
        #expect(controller.isPopoverVisible == true)
        #expect(controller.overlayWindow.ignoresMouseEvents == true)
    }

    @Test("global mouse down detects clicks in highlighted text range")
    func globalMouseDownDetectsHighlightRange() throws {
        let text = "Ths is a tset."
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let view = UnderlineView()
        view.entries = [
            UnderlineEntry(
                underlineRect: NSRect(x: 10, y: 10, width: 80, height: 2),
                hitRect: UnderlineView.expandedHitRect(from: NSRect(x: 10, y: 10, width: 80, height: 2)),
                suggestion: suggestion,
                highlightRect: NSRect(x: 8, y: 10, width: 84, height: 18)
            )
        ]
        controller.underlineView = view
        controller.overlayWindow.setFrame(NSRect(x: 100, y: 200, width: 120, height: 80), display: false)

        let handled = controller.handleGlobalMouseDown(screenPoint: NSPoint(x: 120, y: 225))
        #expect(handled == true)
        #expect(controller.isPopoverVisible == true)
    }

    @Test("global mouse move highlights text range over underline")
    func globalMouseMoveHighlightsUnderline() throws {
        let text = "Ths is a tset."
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        let view = UnderlineView()
        view.entries = [
            UnderlineEntry(
                underlineRect: NSRect(x: 10, y: 10, width: 80, height: 2),
                hitRect: UnderlineView.expandedHitRect(from: NSRect(x: 10, y: 10, width: 80, height: 2)),
                suggestion: suggestion,
                highlightRect: NSRect(x: 8, y: 10, width: 84, height: 18)
            )
        ]
        controller.underlineView = view
        controller.overlayWindow.setFrame(NSRect(x: 100, y: 200, width: 120, height: 80), display: false)

        let hoveredID = controller.handleGlobalMouseMoved(screenPoint: NSPoint(x: 120, y: 225))
        #expect(hoveredID == suggestion.id)
        #expect(view.hoveredSuggestionID == suggestion.id)

        _ = controller.handleGlobalMouseMoved(screenPoint: NSPoint(x: 20, y: 20))
        #expect(view.hoveredSuggestionID == nil)
    }

    @Test("global mouse down detects LLM dashed underline hit band")
    func globalMouseDownDetectsLLMUnderlineHitBand() throws {
        let text = "Ths is a tset."
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeDiffSuggestion(
            in: text,
            scalarStart: 0,
            scalarLength: 3,
            original: "Ths",
            category: .rephrase,
            source: .llm
        )
        let view = UnderlineView()
        view.entries = [
            UnderlineEntry(
                underlineRect: NSRect(x: 10, y: 10, width: 80, height: 2),
                hitRect: UnderlineView.expandedHitRect(from: NSRect(x: 10, y: 10, width: 80, height: 2)),
                suggestion: suggestion
            )
        ]
        controller.underlineView = view
        controller.overlayWindow.setFrame(NSRect(x: 100, y: 200, width: 120, height: 80), display: false)

        let handled = controller.handleGlobalMouseDown(screenPoint: NSPoint(x: 120, y: 211))
        #expect(handled == true)
        #expect(controller.overlayWindow.ignoresMouseEvents == true)
    }

    @Test("LLM click dispatches card even when stored paragraph hash does not match overlay splitter")
    func llmClickDispatchesWithParagraphHashMismatch() throws {
        let text = "First line\nSecond line with a style suggestion"
        let range = text.startIndex..<text.endIndex
        let mismatchedHash = ParagraphHash(bundleID: "com.test", paragraphText: "Second line with a style suggestion")
        let suggestion = Suggestion(
            id: UUID(),
            range: range,
            original: text,
            primaryReplacement: "First line. Second line has a clearer style suggestion.",
            allReplacements: ["First line. Second line has a clearer style suggestion."],
            message: "Improve flow.",
            category: .rephrase,
            source: .llm,
            priority: 8,
            paragraphHash: mismatchedHash
        )
        let controller = OverlayController(
            accessor: MockAXAccessor(),
            textMonitor: makeDiffMonitor()
        )
        controller.textContext = makeContext(text: text)
        controller.suggestions = [suggestion]

        let view = UnderlineView()
        view.entries = [
            UnderlineEntry(
                underlineRect: NSRect(x: 10, y: 10, width: 120, height: 2),
                hitRect: UnderlineView.expandedHitRect(from: NSRect(x: 10, y: 10, width: 120, height: 2)),
                suggestion: suggestion
            )
        ]
        controller.underlineView = view
        controller.overlayWindow.contentView = view
        controller.overlayWindow.setFrame(NSRect(x: 100, y: 200, width: 160, height: 80), display: false)

        let handled = controller.handleGlobalMouseDown(screenPoint: NSPoint(x: 120, y: 211))

        #expect(handled == true)
        #expect(controller.hiddenParagraphScalarRange != nil)
        controller.dismiss()
    }

    // Test 5: empty new suggestions calls dismiss()
    @Test("update with empty suggestions dismisses the overlay")
    func updateEmptySuggestionsDismisses() throws {
        let text = "Ths is a tset."
        let accessor = makeAccessorWithRect()
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)

        let s1 = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        controller.show(suggestions: [s1], context: context)
        #expect(controller.suggestions.count == 1)

        // All errors resolved
        controller.update(suggestions: [], context: context)

        #expect(controller.suggestions.isEmpty)
        #expect(controller.textContext == nil)
    }

    // Test 6: context from a different AXUIElement falls through to show()
    @Test("update with different axElement falls through to show()")
    func updateDifferentElementFallsThrough() throws {
        let text = "Ths is a tset."
        let accessor = makeAccessorWithRect()
        let controller = OverlayController(accessor: accessor)
        let context = makeContext(text: text)

        let s1 = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")
        controller.show(suggestions: [s1], context: context)
        #expect(controller.suggestions.count == 1)

        // New context with a different bundleID (simulates field change)
        let newContext = TextContext(
            text: text,
            bundleID: "com.apple.Notes",
            extractionMethod: .axDirectSelection,
            selectionRange: nil,
            elementBounds: nil,
            axElement: AXUIElementCreateSystemWide()
        )
        let s1b = makeDiffSuggestion(in: text, scalarStart: 0, scalarLength: 3, original: "Ths")

        controller.update(suggestions: [s1b], context: newContext)

        // Should have shown fresh — suggestions still present
        #expect(controller.suggestions.count == 1)
        // Context should be updated to the new one
        #expect(controller.textContext?.bundleID == "com.apple.Notes")
    }
}
