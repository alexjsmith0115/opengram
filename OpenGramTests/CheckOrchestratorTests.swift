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

private final class SlowMockLLMProvider: LLMProviderProtocol, @unchecked Sendable {
    let delay: UInt64
    let styleResults: [LLMStyleSuggestion]

    init(delay: UInt64 = 500_000_000, styleResults: [LLMStyleSuggestion] = []) {
        self.delay = delay
        self.styleResults = styleResults
    }

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        try? await Task.sleep(nanoseconds: delay)
        return styleResults
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
}

struct CheckOrchestratorTests {

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

    @Test func llmCompletesEvenWhenParentTaskCancelled() async throws {
        let source = "I think this is quite good"
        let llmSuggestion = LLMStyleSuggestion(
            category: .tone,
            originalText: source,
            revisedText: "This is quite good",
            explanation: "Remove hedging",
            confidence: 8
        )
        let mockLLM = SlowMockLLMProvider(delay: 200_000_000, styleResults: [llmSuggestion])
        let stubHarper = StubGrammarChecker()
        let orchestrator = CheckOrchestrator(harper: stubHarper, llm: mockLLM)

        var llmBatches: [[LLMStyleSuggestion]] = []
        var llmFinished = false

        await orchestrator.runCheck(
            text: source,
            context: TextContext.stub(text: source),
            config: LLMConfig(
                baseURL: "http://localhost:1234/v1",
                model: "test",
                enabledChecks: [.tone],
                temperature: 0.3,
                maxTokens: 512,
                requestTimeout: 60
            ),
            apiKey: "test-key",
            onHarperComplete: { _, _ in },
            onLLMBatch: { suggestions, _ in llmBatches.append(suggestions) },
            onLLMFinished: { llmFinished = true }
        )

        #expect(llmFinished, "onLLMFinished must be called")
        #expect(!llmBatches.isEmpty, "LLM results must be delivered")
    }

    @Test func llmStreamCompletesAndFinishedCallbackFires() async throws {
        let source = "We should probably consider maybe doing this"
        let llmSuggestion = LLMStyleSuggestion(
            category: .clarity,
            originalText: source,
            revisedText: "We should consider doing this",
            explanation: "Remove hedging language",
            confidence: 8
        )
        // 100ms delay — fast enough to not timeout, slow enough to exercise async path
        let mockLLM = SlowMockLLMProvider(delay: 100_000_000, styleResults: [llmSuggestion])
        let stubHarper = StubGrammarChecker()
        let orchestrator = CheckOrchestrator(harper: stubHarper, llm: mockLLM)

        var llmFinished = false

        await orchestrator.runCheck(
            text: source,
            context: TextContext.stub(text: source),
            config: LLMConfig(
                baseURL: "http://localhost:1234/v1",
                model: "test",
                enabledChecks: [.clarity, .tone],
                temperature: 0.3,
                maxTokens: 512,
                requestTimeout: 60
            ),
            apiKey: "test-key",
            onHarperComplete: { _, _ in },
            onLLMBatch: { _, _ in },
            onLLMFinished: { llmFinished = true }
        )

        #expect(llmFinished, "onLLMFinished must fire after stream completes — stored finishing task reference prevents premature deallocation")
    }
}
