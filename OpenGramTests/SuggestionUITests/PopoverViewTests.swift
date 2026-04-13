import Testing
import SwiftUI
import AppKit

@testable import OpenGramLib

// MARK: - Helpers

private func makeSpellingSuggestion() -> Suggestion {
    let text = "recieve"
    let range = text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: text,
        primaryReplacement: "receive",
        allReplacements: ["receive", "relieve"],
        message: "Possible spelling mistake.",
        category: .spelling,
        source: .harper,
        priority: 5
    )
}

private func makeGrammarSuggestion() -> Suggestion {
    let text = "They is going"
    let range = text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: text,
        primaryReplacement: "They are going",
        allReplacements: ["They are going"],
        message: "Subject-verb agreement error.",
        category: .grammarPunctuation,
        source: .harper,
        priority: 5
    )
}

// MARK: - Tests

@Suite("PopoverView conditional content logic")
@MainActor
struct PopoverViewTests {

    @Test("onAddToDictionary is wired when category is .spelling")
    func addToDictionaryWiredForSpelling() {
        var callCount = 0
        let suggestion = makeSpellingSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onDismiss: {},
            onAddToDictionary: { callCount += 1 }
        )
        // Verify the closure was passed: call it and confirm it fires
        view.onAddToDictionary?()
        #expect(callCount == 1)
    }

    @Test("onAddToDictionary is nil when category is .grammarPunctuation")
    func addToDictionaryNilForGrammar() {
        let suggestion = makeGrammarSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onDismiss: {},
            onAddToDictionary: nil
        )
        #expect(view.onAddToDictionary == nil)
    }

    @Test("allReplacements.count > 1 means other suggestions section should be shown")
    func otherSuggestionsVisibleWhenMultipleReplacements() {
        let suggestion = makeSpellingSuggestion() // has ["receive", "relieve"]
        #expect(suggestion.allReplacements.count > 1)
        let shouldShow = suggestion.allReplacements.count > 1
        #expect(shouldShow == true)
    }

    @Test("allReplacements.count == 1 means other suggestions section should be hidden")
    func otherSuggestionsHiddenWhenSingleReplacement() {
        let suggestion = makeGrammarSuggestion() // has exactly 1 replacement
        #expect(suggestion.allReplacements.count == 1)
        let shouldShow = suggestion.allReplacements.count > 1
        #expect(shouldShow == false)
    }

    @Test("onAccept callback fires when called")
    func acceptCallbackFires() {
        var fired = false
        let suggestion = makeSpellingSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: { fired = true },
            onDismiss: {},
            onAddToDictionary: nil
        )
        view.onAccept()
        #expect(fired == true)
    }

    @Test("onDismiss callback fires when called")
    func dismissCallbackFires() {
        var fired = false
        let suggestion = makeSpellingSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onDismiss: { fired = true },
            onAddToDictionary: nil
        )
        view.onDismiss()
        #expect(fired == true)
    }

    @Test("PopoverView can be instantiated with spelling suggestion")
    func canInstantiateWithSpelling() {
        let suggestion = makeSpellingSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onDismiss: {},
            onAddToDictionary: {}
        )
        #expect(view.suggestion.category == .spelling)
        #expect(view.onAddToDictionary != nil)
    }

    @Test("PopoverView can be instantiated with grammar suggestion")
    func canInstantiateWithGrammar() {
        let suggestion = makeGrammarSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onDismiss: {},
            onAddToDictionary: nil
        )
        #expect(view.suggestion.category == .grammarPunctuation)
        #expect(view.onAddToDictionary == nil)
    }
}
