import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

// Test-only factory for TextContext. The struct requires an AXUIElement which
// has no meaningful value in unit tests. AXUIElementCreateSystemWide() is a
// valid sentinel that doesn't require accessibility permissions to construct.
extension TextContext {
    static func stub(text: String = "") -> TextContext {
        TextContext(
            text: text,
            bundleID: "com.test.stub",
            extractionMethod: .axDirectFull,
            selectionRange: nil,
            elementBounds: nil,
            axElement: AXUIElementCreateSystemWide()
        )
    }
}

// Local mock grammar checker for orchestrator tests. Avoids cross-file dependency
// on the MockGrammarChecker defined in AppDelegateWiringTests.
private final class StubGrammarChecker: GrammarCheckerProtocol, @unchecked Sendable {
    let results: [Suggestion]

    init(results: [Suggestion] = []) {
        self.results = results
    }

    func check(text: String) async -> [Suggestion] { results }
    func addToDictionary(word: String) async {}
    func setRuleEnabled(key: String, enabled: Bool) async {}
}

struct CheckOrchestratorTests {

    // Helper to create a Suggestion with a specific range in a source string
    private func makeSuggestion(
        original: String,
        in source: String,
        category: CheckCategory = .tone,
        suggestionSource: SuggestionSource = .llm
    ) -> Suggestion? {
        guard let range = source.range(of: original) else { return nil }
        return Suggestion(
            id: UUID(),
            range: range,
            original: original,
            primaryReplacement: "fixed",
            allReplacements: ["fixed"],
            message: "test",
            category: category,
            source: suggestionSource,
            priority: 50
        )
    }

    @Test func hardFilterRemovesOverlappingSuggestion() {
        let source = "I think we should sort of do this"
        let harperSuggestion = makeSuggestion(original: "sort of", in: source, category: .grammarPunctuation, suggestionSource: .harper)!
        let llmSuggestion = makeSuggestion(original: "sort of", in: source, category: .tone, suggestionSource: .llm)!

        let filtered = CheckOrchestrator.hardFilter([llmSuggestion], harperRanges: [harperSuggestion.range])
        #expect(filtered.isEmpty)
    }

    @Test func hardFilterKeepsNonOverlapping() {
        let source = "I think we should sort of do this"
        let harperSuggestion = makeSuggestion(original: "sort of", in: source, category: .grammarPunctuation, suggestionSource: .harper)!
        let llmSuggestion = makeSuggestion(original: "I think", in: source, category: .tone, suggestionSource: .llm)!

        let filtered = CheckOrchestrator.hardFilter([llmSuggestion], harperRanges: [harperSuggestion.range])
        #expect(filtered.count == 1)
        #expect(filtered[0].original == "I think")
    }

    @Test func hardFilterWithEmptyHarperRanges() {
        let source = "I think we should do this"
        let llmSuggestion = makeSuggestion(original: "I think", in: source)!

        let filtered = CheckOrchestrator.hardFilter([llmSuggestion], harperRanges: [])
        #expect(filtered.count == 1)
    }

    @Test func hardFilterWithEmptyLLMSuggestions() {
        let source = "I think we should do this"
        let harperSuggestion = makeSuggestion(original: "I think", in: source, suggestionSource: .harper)!

        let filtered = CheckOrchestrator.hardFilter([], harperRanges: [harperSuggestion.range])
        #expect(filtered.isEmpty)
    }

    @Test func harperOnlyModeWhenLLMNil() async {
        // LLM-07: App remains fully functional when LLM is not configured
        let stubHarper = StubGrammarChecker(results: [
            Suggestion(
                id: UUID(),
                range: "hello world".range(of: "hello")!,
                original: "hello",
                primaryReplacement: "Hello",
                allReplacements: ["Hello"],
                message: "Capitalize",
                category: .spelling,
                source: .harper,
                priority: 100
            )
        ])
        let orchestrator = CheckOrchestrator(harper: stubHarper, llm: nil)

        var harperResults: [Suggestion] = []
        var llmFinishedCalled = false

        await orchestrator.runCheck(
            text: "hello world",
            context: TextContext.stub(),
            config: .default,
            apiKey: nil,
            onHarperComplete: { suggestions, _ in harperResults = suggestions },
            onLLMBatch: { _, _ in },
            onLLMFinished: { llmFinishedCalled = true }
        )

        #expect(harperResults.count == 1)
        #expect(harperResults[0].original == "hello")
        #expect(llmFinishedCalled, "onLLMFinished must be called even when LLM is nil")
    }
}
