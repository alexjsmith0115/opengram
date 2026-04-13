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

    @Test("acceptSuggestion calls setAttributeValue with range then replacement on success")
    func acceptWritesRangeThenReplacement() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        // Return updated text so repositionAfterAccept can re-read it
        mock.attributeValues[kAXValueAttribute] = (.success, "receive the tset" as CFString)

        let controller = OverlayController(accessor: mock)
        let text = "recieve the tset"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        #expect(mock.setAttributeCalls.count == 2)
        #expect(mock.setAttributeCalls[0].attribute == kAXSelectedTextRangeAttribute)
        #expect(mock.setAttributeCalls[1].attribute == kAXSelectedTextAttribute)
    }

    @Test("acceptSuggestion returns without modifying suggestions when AX range selection fails")
    func acceptDoesNothingWhenRangeSelectFails() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .failure

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.acceptSuggestion(suggestion, context: context)

        // Suggestion must remain because the write failed
        #expect(controller.suggestions.count == 1)
    }

    @Test("acceptSuggestion removes accepted suggestion from suggestions array on success")
    func acceptRemovesSuggestion() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeValues[kAXValueAttribute] = (.success, "receive the tset" as CFString)

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
        // No remaining suggestions -- reposition not needed
        mock.attributeValues[kAXValueAttribute] = (.success, "receive" as CFString)

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
        // After accepting "aaa" (3 chars) replaced with "abcd" (4 chars), the text shifts by +1
        // Original: "aaa bb ccc" -> "abcd bb ccc"
        mock.attributeValues[kAXValueAttribute] = (.success, "abcd bb ccc" as CFString)

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
        // Accept s2 ("bb" -> "B"), delta = -1. s1 is before accepted range -- unchanged.
        // "aaa bb ccc" -> "aaa B ccc"
        mock.attributeValues[kAXValueAttribute] = (.success, "aaa B ccc" as CFString)

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
}

// MARK: - Keyboard Navigation Tests

@Suite("OverlayController keyboard navigation")
@MainActor
struct OverlayControllerKeyboardTests {

    @Test("Tab advances focusedIndex from nil to 0")
    func tabFromNilToZero() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion(original: "aaa")
        let s2 = makeSuggestion(original: "bbb")
        controller.suggestions = [s1, s2]
        controller.handleTab()
        #expect(controller.focusedIndex == 0)
    }

    @Test("Tab advances focusedIndex from 0 to 1")
    func tabFromZeroToOne() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion(original: "aaa")
        let s2 = makeSuggestion(original: "bbb")
        controller.suggestions = [s1, s2]
        controller.focusedIndex = 0
        controller.handleTab()
        #expect(controller.focusedIndex == 1)
    }

    @Test("Tab wraps from last index back to 0")
    func tabWrapsAround() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion(original: "aaa")
        let s2 = makeSuggestion(original: "bbb")
        controller.suggestions = [s1, s2]
        controller.focusedIndex = 1
        controller.handleTab()
        #expect(controller.focusedIndex == 0)
    }

    @Test("Enter with focusedIndex set and no popover opens popover for focused suggestion")
    func enterWithFocusOpensPopover() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion(original: "aaa")
        controller.suggestions = [s1]
        controller.focusedIndex = 0
        controller.handleEnter(textContext: nil)
        #expect(controller.isPopoverVisible == true)
        #expect(controller.currentPopoverSuggestion?.id == s1.id)
    }

    @Test("Enter with popover open calls acceptSuggestion for current suggestion")
    func enterWithPopoverAccepts() {
        let mock = MockAXAccessor()
        mock.setAttributeResult = .success
        mock.attributeValues[kAXValueAttribute] = (.success, "receive" as CFString)

        let controller = OverlayController(accessor: mock)
        let text = "recieve"
        let context = makeTextContext(text: text)
        let suggestion = makeSuggestion(in: text, scalarStart: 0, scalarLength: 7,
                                        primaryReplacement: "receive")
        controller.suggestions = [suggestion]
        controller.showPopover(for: suggestion)
        #expect(controller.isPopoverVisible == true)

        controller.handleEnter(textContext: context)

        // Suggestion should be removed (accepted) -- signals acceptSuggestion was called
        #expect(controller.suggestions.isEmpty)
    }

    @Test("Escape with popover open closes popover but does not dismiss overlay")
    func escapeWithPopoverClosesPopover() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.showPopover(for: s1)
        controller.handleEscape(textContext: nil)
        #expect(controller.isPopoverVisible == false)
        // Overlay still has suggestions
        #expect(controller.suggestions.count == 1)
    }

    @Test("Escape with no popover open dismisses all")
    func escapeWithNoPopoverDismissesAll() {
        let controller = OverlayController(accessor: MockAXAccessor())
        let s1 = makeSuggestion()
        controller.suggestions = [s1]
        controller.handleEscape(textContext: nil)
        #expect(controller.suggestions.isEmpty)
        #expect(controller.isPopoverVisible == false)
    }
}
