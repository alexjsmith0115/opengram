import Testing
import AppKit
@preconcurrency import ApplicationServices

@testable import OpenGramLib

// MARK: - Helpers

private func makeSuggestion(
    category: CheckCategory = .spelling,
    original: String = "recieve"
) -> Suggestion {
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: original,
        primaryReplacement: "receive",
        allReplacements: ["receive"],
        message: "Spelling error.",
        category: category,
        source: .harper,
        priority: 5
    )
}

private func makeTextContext() -> TextContext {
    TextContext(
        text: "recieve",
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
        let controller = OverlayController(accessor: MockAXAccessor())
        var acceptedSuggestion: Suggestion?
        controller.onAcceptSuggestion = { acceptedSuggestion = $0 }

        let s1 = makeSuggestion()
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
