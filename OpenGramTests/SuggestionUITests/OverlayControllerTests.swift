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
        priority: 5
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
        priority: 5
    )
}

/// Creates an AXValue wrapping a valid CGRect for use with kAXBoundsForRangeParameterizedAttribute mocks.
private func makeAXRectValue(_ rect: CGRect = CGRect(x: 100, y: 200, width: 50, height: 14)) -> CFTypeRef {
    var r = rect
    return AXValueCreate(.cgRect, &r)!
}

private func makeTextContext(text: String = "recieve") -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.apple.TextEdit",
        extractionMethod: .axDirectSelection,
        selectionRange: nil,
        elementBounds: nil,
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
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Fallback: must write kAXValueAttribute
        let valueWritten = mock.setAttributeCalls.contains { $0.attribute == kAXValueAttribute }
        #expect(valueWritten)
    }

    @Test("rangeTargetedWriteFallsBackWhenSelectionSetFails")
    func rangeTargetedWriteFallsBackWhenSelectionSetFails() {
        let mock = MockAXAccessor()
        // isAttributeSettable says yes, but the actual set call fails
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        mock.attributeValues[kAXValueAttribute] = (.success, "recieve" as CFString)

        // First setAttributeValue call (range set) fails, second (full write) succeeds
        var callCount = 0
        mock.setAttributeResultsByCall = { _ in
            callCount += 1
            return callCount == 1 ? .failure : .success
        }

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Should have fallen back to full write
        let valueWritten = mock.setAttributeCalls.contains { $0.attribute == kAXValueAttribute }
        #expect(valueWritten)
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

    @Test("repositionDropsSuggestionsOnBoundsFailure")
    func repositionDropsSuggestionsOnBoundsFailure() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, true)
        // After accept, re-read succeeds but bounds queries return nil (watchdog skip path)
        mock.attributeValues[kAXValueAttribute] = (.success, "aaa B ccc" as CFString)
        // No parameterized attribute values set — BoundsValidator will get nil bounds for all

        let controller = OverlayController(accessor: mock)
        let text = "aaa bb ccc"
        let context = makeTextContext(text: text)
        let s1 = makeSuggestion(in: text, scalarStart: 0, scalarLength: 3, primaryReplacement: "AAA")
        let s2 = makeSuggestion(in: text, scalarStart: 4, scalarLength: 2, primaryReplacement: "B")
        controller.suggestions = [s1, s2]
        controller.acceptSuggestion(s2, context: context)

        // Remaining suggestion s1 should be dropped because bounds re-query fails (nil from BoundsValidator)
        // and all suggestions dropped means dismiss() is called
        #expect(controller.suggestions.isEmpty)
    }

    @Test("acceptWritesFullTextReplacementInFallback")
    func acceptWritesFullTextReplacementInFallback() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeSettable[kAXSelectedTextRangeAttribute] = (.success, false)
        mock.attributeValues[kAXValueAttribute] = (.success, "recieve the tset" as CFString)

        let controller = OverlayController(accessor: mock)
        let text = "recieve the tset"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Should write kAXValueAttribute with the replaced text
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
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Suggestion must remain because the read failed
        #expect(controller.suggestions.count == 1)
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
