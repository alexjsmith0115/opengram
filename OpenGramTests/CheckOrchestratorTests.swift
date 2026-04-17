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

    @Test func harperOnlyModeDeliversResults() async {
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
                priority: 100,
                paragraphHash: nil
            )
        ])
        let orchestrator = CheckOrchestrator(harper: stubHarper)

        var harperResults: [Suggestion] = []
        var llmFinishedCalled = false

        await orchestrator.runCheck(
            text: "hello world",
            context: TextContext.stub(),
            onHarperComplete: { suggestions, _ in harperResults = suggestions },
            onLLMFinished: { llmFinishedCalled = true }
        )

        #expect(harperResults.count == 1)
        #expect(harperResults[0].original == "hello")
        #expect(llmFinishedCalled, "onLLMFinished must be called after runCheck")
    }
}
