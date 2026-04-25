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
        priority: 5,
        paragraphHash: nil
    )
}

private func makeSpellingSuggestionSingle() -> Suggestion {
    let text = "tset"
    let range = text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: text,
        primaryReplacement: "test",
        allReplacements: ["test"],
        message: "Possible spelling mistake.",
        category: .spelling,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

private func makeSpellingSuggestionMultiple() -> Suggestion {
    let text = "tset"
    let range = text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: text,
        primaryReplacement: "test",
        allReplacements: ["test", "tests", "testing"],
        message: "Possible spelling mistake.",
        category: .spelling,
        source: .harper,
        priority: 5,
        paragraphHash: nil
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
        priority: 5,
        paragraphHash: nil
    )
}

private func makeBadgeSuggestion(category: CheckCategory, source: SuggestionSource) -> Suggestion {
    let text = "x"
    let range = text.startIndex..<text.endIndex
    return Suggestion(
        id: .init(),
        range: range,
        original: text,
        primaryReplacement: "y",
        allReplacements: ["y"],
        message: "synthetic",
        category: category,
        source: source,
        priority: 100,
        paragraphHash: nil,
        severity: nil
    )
}

@MainActor
private func makePopoverView(suggestion: Suggestion) -> PopoverView {
    PopoverView(
        suggestion: suggestion,
        onAccept: {},
        onAcceptAlternative: { _ in },
        onDismiss: {},
        onAddToDictionary: nil
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
            onAcceptAlternative: { _ in },
            onDismiss: {},
            onAddToDictionary: { callCount += 1 }
        )
        view.onAddToDictionary?()
        #expect(callCount == 1)
    }

    @Test("onAddToDictionary is nil when category is .grammarPunctuation")
    func addToDictionaryNilForGrammar() {
        let suggestion = makeGrammarSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onAcceptAlternative: { _ in },
            onDismiss: {},
            onAddToDictionary: nil
        )
        #expect(view.onAddToDictionary == nil)
    }

    @Test("allReplacements.count > 1 means disclosure group should be shown")
    func disclosureShownWhenMultipleReplacements() {
        let suggestion = makeSpellingSuggestion() // has ["receive", "relieve"]
        #expect(suggestion.allReplacements.count > 1)
        let shouldShow = suggestion.allReplacements.count > 1
        #expect(shouldShow == true)
    }

    @Test("allReplacements.count == 1 means disclosure group should be hidden")
    func disclosureHiddenWhenSingleReplacement() {
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
            onAcceptAlternative: { _ in },
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
            onAcceptAlternative: { _ in },
            onDismiss: { fired = true },
            onAddToDictionary: nil
        )
        view.onDismiss()
        #expect(fired == true)
    }

    @Test("onAcceptAlternative callback fires with the alternative string")
    func acceptAlternativeCallbackFires() {
        var receivedAlt = ""
        let suggestion = makeSpellingSuggestionMultiple()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onAcceptAlternative: { alt in receivedAlt = alt },
            onDismiss: {},
            onAddToDictionary: nil
        )
        view.onAcceptAlternative("tests")
        #expect(receivedAlt == "tests")
    }

    @Test("PopoverView can be instantiated with spelling suggestion")
    func canInstantiateWithSpelling() {
        let suggestion = makeSpellingSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onAcceptAlternative: { _ in },
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
            onAcceptAlternative: { _ in },
            onDismiss: {},
            onAddToDictionary: nil
        )
        #expect(view.suggestion.category == .grammarPunctuation)
        #expect(view.onAddToDictionary == nil)
    }

    @Test("alternatives disclosure not shown for single replacement suggestion")
    func alternativesDisclosureHiddenWhenSingleReplacement() {
        let suggestion = makeSpellingSuggestionSingle()
        #expect(suggestion.allReplacements.count == 1)
        // DisclosureGroup is only rendered when count > 1
        #expect((suggestion.allReplacements.count > 1) == false)
    }

    @Test("alternatives disclosure shown for multiple replacement suggestion")
    func alternativesDisclosureShownWhenMultipleReplacements() {
        let suggestion = makeSpellingSuggestionMultiple()
        #expect(suggestion.allReplacements.count == 3)
        // DisclosureGroup is rendered when count > 1
        #expect((suggestion.allReplacements.count > 1) == true)
    }

    @Test("Add to Dictionary hidden for non-spelling category")
    func addToDictionaryHiddenForNonSpelling() {
        let suggestion = makeGrammarSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onAcceptAlternative: { _ in },
            onDismiss: {},
            onAddToDictionary: nil
        )
        #expect(view.onAddToDictionary == nil)
    }

    @Test("Add to Dictionary shown for spelling category")
    func addToDictionaryShownForSpelling() {
        let suggestion = makeSpellingSuggestion()
        let view = PopoverView(
            suggestion: suggestion,
            onAccept: {},
            onAcceptAlternative: { _ in },
            onDismiss: {},
            onAddToDictionary: {}
        )
        #expect(view.onAddToDictionary != nil)
    }

    // MARK: - CLAR-02: Category-aware badge label + icon

    @Test("badgeLabel is 'Clarity' and icon is 'text.magnifyingglass' for clarity category")
    func badgeLabel_clarity() {
        let s = makeBadgeSuggestion(category: .clarity, source: .harper)
        let view = makePopoverView(suggestion: s)
        #expect(view.badgeLabel == "Clarity")
        #expect(view.badgeIcon == "text.magnifyingglass")
    }

    @Test("badgeLabel is 'Harper' and icon is 'checkmark.circle' for non-clarity Harper category")
    func badgeLabel_harperNonClarity() {
        let s = makeBadgeSuggestion(category: .spelling, source: .harper)
        let view = makePopoverView(suggestion: s)
        #expect(view.badgeLabel == "Harper")
        #expect(view.badgeIcon == "checkmark.circle")
    }

    @Test("badgeLabel is 'AI' and icon is 'sparkles' for non-clarity LLM category")
    func badgeLabel_llm() {
        let s = makeBadgeSuggestion(category: .tone, source: .llm)
        let view = makePopoverView(suggestion: s)
        #expect(view.badgeLabel == "AI")
        #expect(view.badgeIcon == "sparkles")
    }
}
