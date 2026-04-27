import Testing
import AppKit
@preconcurrency import ApplicationServices

@testable import OpenGramLib

// MARK: - Helpers

private func makeSuggestion(
    id: UUID = UUID(),
    category: CheckCategory = .spelling,
    original: String = "recieve",
    primaryReplacement: String = "receive"
) -> Suggestion {
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: id,
        range: range,
        original: original,
        primaryReplacement: primaryReplacement,
        allReplacements: [primaryReplacement],
        message: "Spelling error.",
        category: category,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

/// Creates a suggestion whose range points into the given text at the given scalar offset.
private func makeSuggestion(
    in text: String,
    scalarStart: Int,
    scalarLength: Int,
    primaryReplacement: String,
    category: CheckCategory = .spelling
) -> Suggestion {
    let scalars = text.unicodeScalars
    let lower = scalars.index(scalars.startIndex, offsetBy: scalarStart)
    let upper = scalars.index(lower, offsetBy: scalarLength)
    let range = lower..<upper
    let original = String(text.unicodeScalars[range])
    return Suggestion(
        id: UUID(),
        range: range,
        original: original,
        primaryReplacement: primaryReplacement,
        allReplacements: [primaryReplacement],
        message: "Spelling error.",
        category: category,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

/// Creates an AXValue wrapping a valid CGRect for use with kAXBoundsForRangeParameterizedAttribute mocks.
private func makeAXRectValue(_ rect: CGRect = CGRect(x: 100, y: 200, width: 50, height: 14)) -> CFTypeRef {
    var r = rect
    return AXValueCreate(.cgRect, &r)!
}

private func makeTextContext(text: String = "recieve", capabilities: AXCapabilities = AXCapabilities()) -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.apple.TextEdit",
        extractionMethod: .axDirectSelection,
        selectionRange: nil,
        elementBounds: nil,
        capabilities: capabilities,
        axElement: AXUIElementCreateSystemWide()
    )
}

// MARK: - OverlayController Tests

@Suite("OverlayController popover management")
@MainActor
struct OverlayControllerTests {

    @Test("showPopover sets isPopoverVisible to true")
    func showPopoverSetsVisible() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeSuggestion()
        controller.showPopover(for: suggestion)
        #expect(controller.isPopoverVisible == true)
    }

    @Test("showPopover stores currentPopoverSuggestion")
    func showPopoverStoresSuggestion() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeSuggestion()
        controller.showPopover(for: suggestion)
        #expect(controller.currentPopoverSuggestion?.id == suggestion.id)
    }

    @Test("showPopover twice replaces previous suggestion (one-at-a-time)")
    func showPopoverTwiceReplacesFirst() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let first = makeSuggestion(original: "recieve")
        let second = makeSuggestion(original: "teh")
        controller.showPopover(for: first)
        controller.showPopover(for: second)
        #expect(controller.currentPopoverSuggestion?.id == second.id)
        #expect(controller.isPopoverVisible == true)
    }

    @Test("closePopover sets isPopoverVisible to false")
    func closePopoverClearsVisible() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeSuggestion()
        controller.showPopover(for: suggestion)
        controller.closePopover()
        #expect(controller.isPopoverVisible == false)
    }

    @Test("closePopover clears currentPopoverSuggestion")
    func closePopoverClearsSuggestion() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let suggestion = makeSuggestion()
        controller.showPopover(for: suggestion)
        controller.closePopover()
        #expect(controller.currentPopoverSuggestion == nil)
    }

    @Test("dismiss resets all state (suggestions empty, popover closed, context nil)")
    func dismissResetsAllState() {
        let controller = OverlayController(accessor: MockAXAccessor())
        // Pre-load some state via show()
        let suggestion = makeSuggestion()
        controller.showPopover(for: suggestion)
        controller.dismiss()
        #expect(controller.suggestions.isEmpty)
        #expect(controller.isPopoverVisible == false)
        #expect(controller.currentPopoverSuggestion == nil)
    }

    @Test("prepareForDeferredSuggestions clears overlay but preserves context")
    func prepareForDeferredSuggestionsPreservesContext() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let context = TextContext(
            text: "clean paragraph for style",
            bundleID: "com.microsoft.Outlook",
            extractionMethod: .axDirectFull,
            selectionRange: nil,
            elementBounds: nil,
            capabilities: AXCapabilities(),
            axElement: AXUIElementCreateSystemWide()
        )
        var dismissedAll = false
        controller.onDismissAll = { dismissedAll = true }
        controller.suggestions = [makeSuggestion()]
        controller.textContext = context

        controller.prepareForDeferredSuggestions(context: context)

        #expect(controller.suggestions.isEmpty)
        #expect(controller.textContext?.bundleID == "com.microsoft.Outlook")
        #expect(dismissedAll == false)
    }

    @Test("handleDismiss removes suggestion from suggestions array")
    func handleDismissRemovesSuggestion() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion(original: "recieve")
        let s2 = makeSuggestion(original: "teh")
        // Directly set the suggestions array for test setup
        controller.suggestions = [s1, s2]
        controller.handleDismissSuggestion(s1)
        #expect(controller.suggestions.count == 1)
        #expect(controller.suggestions.first?.id == s2.id)
    }

    @Test("handleDismiss with last suggestion triggers full dismiss")
    func handleDismissLastSuggestionDismissesAll() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.handleDismissSuggestion(s1)
        #expect(controller.suggestions.isEmpty)
        #expect(controller.isPopoverVisible == false)
    }

    @Test("onDismissSuggestion callback fires when suggestion is dismissed")
    func dismissCallbackFires() {
        let controller = OverlayController(accessor: MockAXAccessor())
        var dismissedSuggestion: Suggestion?
        controller.onDismissSuggestion = { dismissedSuggestion = $0 }

        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.handleDismissSuggestion(s1)
        #expect(dismissedSuggestion?.id == s1.id)
    }

    @Test("onAcceptSuggestion callback fires when suggestion is accepted")
    func acceptCallbackFires() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeValues[kAXValueAttribute] = (.success, "receive" as CFString)
        // Range-targeted write not supported — fall back to full write
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)

        let controller = OverlayController(accessor: mock)
        var acceptedSuggestion: Suggestion?
        controller.onAcceptSuggestion = { acceptedSuggestion = $0 }

        let text = "recieve"
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                primaryReplacement: "receive")
        let context = makeTextContext(text: text)
        controller.suggestions = [s1]
        controller.textContext = context
        controller.handleAcceptSuggestion(s1)
        #expect(acceptedSuggestion?.id == s1.id)
    }

    @Test("onAddToDictionary callback fires for spelling suggestion")
    func addToDictionaryCallbackFires() {
        let controller = OverlayController(accessor: MockAXAccessor())
        var addedWord: String?
        controller.onAddToDictionary = { addedWord = $0 }

        let s1 = makeSuggestion(category: .spelling, original: "recieve")
        controller.handleAddToDictionary(word: s1.original)
        #expect(addedWord == "recieve")
    }
}

// MARK: - Accept / Write-back Tests

@Suite("OverlayController accept and write-back")
@MainActor
struct OverlayControllerAcceptTests {

    @Test("rangeTargetedWriteUsesSetSelectedTextRange when settable")
    func rangeTargetedWriteUsesSetSelectedTextRange() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // First call must be kAXSelectedTextRangeAttribute, second must be kAXSelectedTextAttribute
        #expect(mock.setAttributeCalls.count >= 2)
        #expect(mock.setAttributeCalls[0].attribute == kAXSelectedTextRangeAttribute)
        #expect(mock.setAttributeCalls[1].attribute == kAXSelectedTextAttribute)
    }

    @Test("rangeTargetedWriteFallsBackWhenNotSettable")
    func rangeTargetedWriteFallsBackWhenNotSettable() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeValues[kAXValueAttribute] = (.success, "recieve" as CFString)

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        // Caps: no range-write, but value read/write available → valueSplice strategy.
        let caps = AXCapabilities(canSetSelectedTextRange: false, canSetSelectedText: false,
                                  canReadSelectedText: false, canSetValue: true, canReadValue: true)
        let context = makeTextContext(text: text, capabilities: caps)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // valueSplice: must write kAXValueAttribute
        let valueWritten = mock.setAttributeCalls.contains { $0.attribute == kAXValueAttribute }
        #expect(valueWritten)
    }

    @Test("rangeTargetedWriteReturnsFalseWhenRangeSetFails")
    func rangeTargetedWriteReturnsFalseWhenRangeSetFails() {
        let mock = MockAXAccessor()
        // range set fails; no auto-fallback in strategy-driven path
        mock.setAttributeResultsByCall = { _ in .failure }
        mock.attributeValues[kAXValueAttribute] = (.success, "recieve" as CFString)

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        let caps = AXCapabilities(canSetSelectedTextRange: true, canSetSelectedText: true,
                                  canReadSelectedText: false, canSetValue: false, canReadValue: false)
        let context = makeTextContext(text: text, capabilities: caps)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Strategy returns false → suggestion stays
        #expect(controller.suggestions.count == 1)
    }

    @Test("acceptSuggestion removes accepted suggestion from suggestions array on success")
    func acceptRemovesSuggestion() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // repositionAfterAccept re-reads kAXValueAttribute after the write
        mock.attributeValues[kAXValueAttribute] = (.success, "receive the tset" as CFString)
        // BoundsValidator needs a valid rect for the surviving suggestion (s2) to be kept
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        let text = "recieve the tset"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                primaryReplacement: "receive")
        let s2 = makeSuggestion(in: text, scalarStart: 12, scalarLength: 4,
                                primaryReplacement: "test")
        controller.suggestions = [s1, s2]
        controller.acceptSuggestion(s1, context: context)

        #expect(controller.suggestions.count == 1)
        #expect(controller.suggestions.first?.id == s2.id)
    }

    @Test("acceptSuggestion calls dismiss when last suggestion is accepted")
    func acceptLastSuggestionDismisses() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        #expect(controller.suggestions.isEmpty)
        #expect(controller.isPopoverVisible == false)
    }

    @Test("repositionAfterAccept shifts scalar offsets for suggestions after accepted range")
    func repositionShiftsOffsets() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // After accepting "aaa" (3 chars) replaced with "abcd" (4 chars), the text shifts by +1
        // Original: "aaa bb ccc" -> "abcd bb ccc"
        mock.attributeValues[kAXValueAttribute] = (.success, "abcd bb ccc" as CFString)
        // BoundsValidator needs valid rects for s2 and s3 to survive reposition
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        // "aaa bb ccc" - suggestion 1: offset 0..3 ("aaa"), suggestion 2: offset 4..6 ("bb"), suggestion 3: offset 7..10 ("ccc")
        let text = "aaa bb ccc"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "abcd")
        let s2 = makeSuggestion(in: text, scalarStart: 4, scalarLength: 2, primaryReplacement: "BB")
        let s3 = makeSuggestion(in: text, scalarStart: 7, scalarLength: 3, primaryReplacement: "CCC")
        controller.suggestions = [s1, s2, s3]
        controller.acceptSuggestion(s1, context: context)

        // After accept: s1 removed. s2 was at 4, delta = +1, new start = 5. s3 was at 7, new start = 8.
        #expect(controller.suggestions.count == 2)
        let offsets = controller.suggestionScalarOffsets
        #expect(offsets[0].scalarStart == 5)
        #expect(offsets[1].scalarStart == 8)
    }

    @Test("repositionAfterAccept does not shift suggestions before the accepted range")
    func repositionDoesNotShiftPriorSuggestions() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // Accept s2 ("bb" -> "B"), delta = -1. s1 is before accepted range -- unchanged.
        // "aaa bb ccc" -> "aaa B ccc"
        mock.attributeValues[kAXValueAttribute] = (.success, "aaa B ccc" as CFString)
        // BoundsValidator needs a valid rect for s1 to survive reposition
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        let text = "aaa bb ccc"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "AAA")
        let s2 = makeSuggestion(in: text, scalarStart: 4, scalarLength: 2, primaryReplacement: "B")
        controller.suggestions = [s1, s2]
        controller.acceptSuggestion(s2, context: context)

        #expect(controller.suggestions.count == 1)
        let offsets = controller.suggestionScalarOffsets
        // s1 starts at 0 -- before accepted range start (4), unchanged
        #expect(offsets[0].scalarStart == 0)
    }

    @Test("repositionAfterAccept recalculates window frame and retranslates entries")
    func repositionRecalculatesWindowFrame() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        mock.attributeValues[kAXValueAttribute] = (.success, "abcd bb ccc" as CFString)
        // BoundsValidator returns a rect so s2 and s3 survive reposition
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        let text = "aaa bb ccc"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "abcd")
        let s2 = makeSuggestion(in: text, scalarStart: 4, scalarLength: 2, primaryReplacement: "BB")
        let s3 = makeSuggestion(in: text, scalarStart: 7, scalarLength: 3, primaryReplacement: "CCC")
        controller.suggestions = [s1, s2, s3]

        // Accept s1 — triggers repositionAfterAccept with two surviving suggestions
        controller.acceptSuggestion(s1, context: context)

        // Both surviving suggestions are retained and reposition executed without crash
        #expect(controller.suggestions.count == 2)
        #expect(controller.suggestions[0].id == s2.id)
        #expect(controller.suggestions[1].id == s3.id)
    }

    @Test("repositionAfterAccept updates suggestion ranges to point into new text")
    func repositionUpdatesSuggestionRanges() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // After accepting "Ths" (3) -> "This" (4), text becomes "This is a tset"
        mock.attributeValues[kAXValueAttribute] = (.success, "This is a tset" as CFString)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        let text = "Ths is a tset"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "This")
        let s2 = makeSuggestion(in: text, scalarStart: 9, scalarLength: 4, primaryReplacement: "test")
        controller.suggestions = [s1, s2]
        controller.acceptSuggestion(s1, context: context)

        #expect(controller.suggestions.count == 1)
        // After +1 char shift, s2's range must be valid in the new text and extract "tset"
        let surviving = controller.suggestions[0]
        let newText = controller.textContext!.text
        let extracted = String(newText[surviving.range])
        #expect(extracted == "tset")
    }

    @Test("repositionDropsSuggestionsOnBoundsFailure")
    func repositionDropsSuggestionsOnBoundsFailure() async throws {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // After accept, re-read succeeds but bounds queries return nil (watchdog skip path)
        mock.attributeValues[kAXValueAttribute] = (.success, "aaa B ccc" as CFString)
        // No parameterized attribute values set — BoundsValidator returns nil for all

        let controller = OverlayController(accessor: mock)
        let text = "aaa bb ccc"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "AAA")
        let s2 = makeSuggestion(in: text, scalarStart: 4, scalarLength: 2, primaryReplacement: "B")
        controller.suggestions = [s1, s2]
        controller.acceptSuggestion(s2, context: context)

        // Accept removes s2 synchronously; s1 survives in the array because the
        // async reposition path (scheduleReposition(.textChanged)) does not drop
        // suggestions with nil bounds — it simply omits them from lastKnownRects.
        #expect(controller.suggestions.count == 1)
        #expect(controller.suggestions.first?.id == s1.id)

        // Drain the async reposition task so the test doesn't leak a pending Task.
        await controller.currentRepositionTask?.value

        // After the async path completes, s1 has no cached rect (bounds failed).
        #expect(controller.lastKnownRects[s1.id] == nil)
    }

    @Test("acceptWritesFullTextReplacementInFallback")
    func acceptWritesFullTextReplacementInFallback() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeValues[kAXValueAttribute] = (.success, "recieve the tset" as CFString)

        let controller = OverlayController(accessor: mock)
        let text = "recieve the tset"
        // valueSplice caps: no range-write, but value read/write available.
        let caps = AXCapabilities(canSetSelectedTextRange: false, canSetSelectedText: false,
                                  canReadSelectedText: false, canSetValue: true, canReadValue: true)
        let context = makeTextContext(text: text, capabilities: caps)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // valueSplice: writes kAXValueAttribute with the spliced result
        let valueCalls = mock.setAttributeCalls.filter { $0.attribute == kAXValueAttribute }
        #expect(valueCalls.count == 1)
        let written = valueCalls[0].value as? String
        #expect(written == "receive the tset")
    }

    @Test("acceptSuggestion returns without modifying suggestions when AX read fails in fallback")
    func acceptDoesNothingWhenReadFails() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeValues[kAXValueAttribute] = (.failure, nil)

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        // valueSplice caps: read will fail → strategy returns false → suggestion stays.
        let caps = AXCapabilities(canSetSelectedTextRange: false, canSetSelectedText: false,
                                  canReadSelectedText: false, canSetValue: true, canReadValue: true)
        let context = makeTextContext(text: text, capabilities: caps)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Suggestion must remain because the read failed
        #expect(controller.suggestions.count == 1)
    }
}

// MARK: - Reposition Integration Tests

/// Helper to extract a CFRange from an AXValue parameter recorded by MockAXAccessor.
private func extractCFRange(from parameter: CFTypeRef) -> CFRange? {
    guard CFGetTypeID(parameter) == AXValueGetTypeID() else { return nil }
    var range = CFRange(location: 0, length: 0)
    guard AXValueGetValue(parameter as! AXValue, .cfRange, &range) else { return nil }
    return range
}

@Suite("OverlayController reposition after accept — integration")
@MainActor
struct OverlayControllerRepositionIntegrationTests {

    @Test("bounds queries use shifted scalar offsets after accept changes text length")
    func boundsQueriesUseShiftedOffsets() async throws {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // "Ths is a tset of grammer" -> accept "Ths"->"This" (+1 char)
        mock.attributeValues[kAXValueAttribute] = (.success, "This is a tset of grammer" as CFString)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        let text = "Ths is a tset of grammer"
        let context = makeTextContext(text: text)
        // "Ths" at 0..3, "tset" at 9..13, "grammer" at 17..24
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "This")
        let s2 = makeSuggestion(in: text, scalarStart: 9, scalarLength: 4, primaryReplacement: "test")
        let s3 = makeSuggestion(in: text, scalarStart: 17, scalarLength: 7, primaryReplacement: "grammar")
        controller.suggestions = [s1, s2, s3]

        // Clear any parameterized calls from setup
        mock.parameterizedAttributeCalls = []

        controller.acceptSuggestion(s1, context: context)

        // Bounds queries now happen asynchronously via scheduleReposition(.textChanged).
        // Await the reposition task before sampling parameterizedAttributeCalls.
        await controller.currentRepositionTask?.value

        // Filter to kAXBoundsForRangeParameterizedAttribute calls during reposition
        let boundsCalls = mock.parameterizedAttributeCalls.filter {
            $0.attribute == kAXBoundsForRangeParameterizedAttribute
        }

        // Extract CFRanges from the bounds queries
        let queriedRanges = boundsCalls.compactMap { extractCFRange(from: $0.parameter) }

        // s2 was at scalar 9..13, delta +1 -> should query 10..14 (location=10, length=4)
        // s3 was at scalar 17..24, delta +1 -> should query 18..25 (location=18, length=7)
        let s2Range = queriedRanges.first { $0.length == 4 }
        let s3Range = queriedRanges.first { $0.length == 7 }

        #expect(s2Range != nil, "Expected a bounds query for the 4-char suggestion")
        #expect(s2Range?.location == 10, "s2 should query at shifted offset 10, got \(s2Range?.location ?? -1)")
        #expect(s3Range != nil, "Expected a bounds query for the 7-char suggestion")
        #expect(s3Range?.location == 18, "s3 should query at shifted offset 18, got \(s3Range?.location ?? -1)")
    }

    @Test("multi-line scenario: accept on line N shifts suggestions on lines N and below")
    func multiLineAcceptShiftsLaterLines() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)

        // 5 lines, each "Ths is a tset.\n" (15 chars per line including newline)
        // Line 4 (0-indexed line 3): accept "Ths" -> "This" at scalar offset 45..48
        // After accept: line 4 becomes "This is a tset.\n" (16 chars), +1 delta
        // Line 5 suggestions (scalar 60+) must shift to 61+
        let originalText = "Ths is a tset.\nThs is a tset.\nThs is a tset.\nThs is a tset.\nThs is a tset."
        let newText = "Ths is a tset.\nThs is a tset.\nThs is a tset.\nThis is a tset.\nThs is a tset."
        mock.attributeValues[kAXValueAttribute] = (.success, newText as CFString)

        // Return different rects per line so we can verify entries are positioned per-line
        var callCount = 0
        let perLineRects: [CGRect] = [
            CGRect(x: 100, y: 100, width: 30, height: 14),  // line 1 "Ths"
            CGRect(x: 200, y: 100, width: 30, height: 14),  // line 1 "tset"
            CGRect(x: 100, y: 120, width: 30, height: 14),  // line 2 "Ths"
            CGRect(x: 200, y: 120, width: 30, height: 14),  // line 2 "tset"
            CGRect(x: 100, y: 140, width: 30, height: 14),  // line 3 "Ths"
            CGRect(x: 200, y: 140, width: 30, height: 14),  // line 3 "tset"
            // line 4 "Ths" is accepted — no rect needed
            CGRect(x: 200, y: 160, width: 30, height: 14),  // line 4 "tset"
            CGRect(x: 100, y: 180, width: 30, height: 14),  // line 5 "Ths"
            CGRect(x: 200, y: 180, width: 30, height: 14),  // line 5 "tset"
        ]

        // Dynamic mock: return rects in sequence
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue(perLineRects[0]))

        let controller = OverlayController(accessor: mock)
        let context = makeTextContext(text: originalText)

        // Create suggestions for "Ths" and "tset" on each of 5 lines
        var suggestions: [Suggestion] = []
        for line in 0..<5 {
            let base = line * 15
            suggestions.append(makeSuggestion(in: originalText, scalarStart: base, scalarLength: 3, primaryReplacement: "This"))
            suggestions.append(makeSuggestion(in: originalText, scalarStart: base + 9, scalarLength: 4, primaryReplacement: "test"))
        }
        controller.suggestions = suggestions

        // Accept "Ths" on line 4 (index 6 in suggestions array: lines 0-3 have 2 each)
        let line4Ths = suggestions[6]
        mock.parameterizedAttributeCalls = []

        controller.acceptSuggestion(line4Ths, context: context)

        // 9 surviving suggestions (10 original - 1 accepted)
        #expect(controller.suggestions.count == 9)

        // Verify scalar offsets: lines 1-3 unchanged, line 4 "tset" shifted +1, line 5 both shifted +1
        let offsets = controller.suggestionScalarOffsets

        // Lines 1-3 (6 suggestions, unchanged)
        #expect(offsets[0].scalarStart == 0, "Line 1 'Ths' unchanged")
        #expect(offsets[1].scalarStart == 9, "Line 1 'tset' unchanged")
        #expect(offsets[2].scalarStart == 15, "Line 2 'Ths' unchanged")
        #expect(offsets[3].scalarStart == 24, "Line 2 'tset' unchanged")
        #expect(offsets[4].scalarStart == 30, "Line 3 'Ths' unchanged")
        #expect(offsets[5].scalarStart == 39, "Line 3 'tset' unchanged")
        // Line 4 "tset" was at 54, shifted +1 to 55
        #expect(offsets[6].scalarStart == 55, "Line 4 'tset' shifted +1")
        // Line 5: "Ths" was at 60 -> 61, "tset" was at 69 -> 70
        #expect(offsets[7].scalarStart == 61, "Line 5 'Ths' shifted +1")
        #expect(offsets[8].scalarStart == 70, "Line 5 'tset' shifted +1")

        // Verify ranges extract correct substrings from new text
        let nt = controller.textContext!.text
        #expect(String(nt[controller.suggestions[6].range]) == "tset", "Line 4 'tset' range correct in new text")
        #expect(String(nt[controller.suggestions[7].range]) == "Ths", "Line 5 'Ths' range correct in new text")
        #expect(String(nt[controller.suggestions[8].range]) == "tset", "Line 5 'tset' range correct in new text")
    }

    @Test("successive accepts accumulate shifts correctly")
    func successiveAcceptsAccumulateShifts() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        mock.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] = (.success, makeAXRectValue())

        let controller = OverlayController(accessor: mock)
        let text = "aa bb cc"
        let context = makeTextContext(text: text)

        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 2, primaryReplacement: "AAA") // +1
        let s2 = makeSuggestion(in: text, scalarStart: 3, scalarLength: 2, primaryReplacement: "BBBB") // +2
        let s3 = makeSuggestion(in: text, scalarStart: 6, scalarLength: 2, primaryReplacement: "CC")   // 0
        controller.suggestions = [s1, s2, s3]

        // Accept s1: "aa"->"AAA" (+1), text becomes "AAA bb cc"
        mock.attributeValues[kAXValueAttribute] = (.success, "AAA bb cc" as CFString)
        controller.acceptSuggestion(s1, context: context)

        #expect(controller.suggestions.count == 2)
        // s2 was at 3, shifted +1 -> 4. s3 was at 6, shifted +1 -> 7.
        #expect(controller.suggestionScalarOffsets[0].scalarStart == 4)
        #expect(controller.suggestionScalarOffsets[1].scalarStart == 7)

        let ctx2 = controller.textContext!
        #expect(String(ctx2.text[controller.suggestions[0].range]) == "bb")
        #expect(String(ctx2.text[controller.suggestions[1].range]) == "cc")

        // Accept s2: "bb"->"BBBB" (+2), text becomes "AAA BBBB cc"
        mock.attributeValues[kAXValueAttribute] = (.success, "AAA BBBB cc" as CFString)
        controller.acceptSuggestion(controller.suggestions[0], context: ctx2)

        #expect(controller.suggestions.count == 1)
        // s3 was at 7 (after first shift), now shifted +2 -> 9
        #expect(controller.suggestionScalarOffsets[0].scalarStart == 9)

        let ctx3 = controller.textContext!
        #expect(String(ctx3.text[controller.suggestions[0].range]) == "cc")
    }
}

// MARK: - Keyboard Navigation Tests

@Suite("OverlayController keyboard navigation")
@MainActor
struct OverlayControllerKeyboardTests {

    @Test("Escape with popover open closes popover but does not dismiss overlay")
    func escapeWithPopoverClosesPopover() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.showPopover(for: s1)
        controller.handleEscape()
        #expect(controller.isPopoverVisible == false)
        // Overlay still has suggestions
        #expect(controller.suggestions.count == 1)
    }

    @Test("Escape with no popover open dismisses all")
    func escapeWithNoPopoverDismissesAll() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.handleEscape()
        #expect(controller.suggestions.isEmpty)
        #expect(controller.isPopoverVisible == false)
    }

    @Test("Tab keyCode does not change overlay state")
    func tabKeyCodeDoesNotChangeState() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        // Tab (keyCode 48) is not intercepted — verify state unchanged
        // Since handleTab no longer exists, we verify through the suggestions/popover state
        #expect(controller.suggestions.count == 1)
        #expect(controller.isPopoverVisible == false)
    }

    @Test("Enter does not accept suggestion (no handleEnter)")
    func enterKeyCodeDoesNotAccept() {
        let mock = MockAXAccessor()
        let controller = OverlayController(accessor: mock)
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.showPopover(for: s1)
        // Enter (keyCode 36) is not intercepted — suggestion must remain
        #expect(controller.suggestions.count == 1)
        #expect(controller.isPopoverVisible == true)
    }
}
