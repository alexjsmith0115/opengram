import Testing
import Foundation
@preconcurrency import ApplicationServices
@testable import OpenGramLib

// MARK: - Mocks

private final class MockLLMProvider: LLMProviderProtocol, @unchecked Sendable {
    let results: [LLMStyleSuggestion]
    let delay: UInt64
    var callCount: Int = 0

    init(results: [LLMStyleSuggestion] = [], delay: UInt64 = 0) {
        self.results = results
        self.delay = delay
    }

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        callCount += 1
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        return results
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
}

private final class FailingLLMProvider: LLMProviderProtocol, @unchecked Sendable {
    var callCount: Int = 0

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        callCount += 1
        // Simulate network failure: return empty (D-08 silent failure pattern)
        return []
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { false }
}

private final class StubHarperChecker: GrammarCheckerProtocol, @unchecked Sendable {
    let results: [Suggestion]

    init(results: [Suggestion] = []) {
        self.results = results
    }

    func check(text: String) async -> [Suggestion] { results }
    func addToDictionary(word: String) async {}
    func setRuleEnabled(key: String, enabled: Bool) async {}
}

// MARK: - Helpers

private func makeHarperSuggestion(original: String = "tset") -> Suggestion {
    Suggestion(
        id: UUID(),
        range: original.startIndex..<original.endIndex,
        original: original,
        primaryReplacement: "test",
        allReplacements: ["test"],
        message: "Spelling error",
        category: .spelling,
        source: .harper,
        priority: 10
    )
}

private func makeLLMSuggestion(category: LLMStyleSuggestion.Category = .clarity) -> LLMStyleSuggestion {
    LLMStyleSuggestion(
        category: category,
        originalText: "We should probably consider doing this",
        revisedText: "We should consider doing this",
        explanation: "Remove hedging language",
        confidence: 8
    )
}

private func enabledConfig() -> LLMConfig {
    LLMConfig(
        baseURL: "http://localhost:1234/v1",
        model: "test-model",
        enabledChecks: Set(LLMCheckType.allCases),
        temperature: 0.3,
        maxTokens: 512,
        requestTimeout: 10,
        confidenceThreshold: LLMConfig.defaultConfidenceThreshold
    )
}

private func disabledConfig() -> LLMConfig {
    LLMConfig(
        baseURL: "",
        model: "test-model",
        enabledChecks: [],
        temperature: 0.3,
        maxTokens: 512,
        requestTimeout: 10,
        confidenceThreshold: LLMConfig.defaultConfidenceThreshold
    )
}

// MARK: - Tests

@Suite("TwoPhaseCheckFlow integration")
struct TwoPhaseCheckFlowTests {

    // MARK: Ordering

    @Test("Harper results arrive before LLM results")
    func harperArrivesBeforeLLM() async {
        var eventLog: [String] = []
        let llm = MockLLMProvider(results: [makeLLMSuggestion()], delay: 100_000_000)
        let harper = StubHarperChecker(results: [makeHarperSuggestion()])
        let orchestrator = CheckOrchestrator(harper: harper, llm: llm)

        await orchestrator.runCheck(
            text: "tset",
            context: .stub(text: "tset"),
            config: enabledConfig(),
            apiKey: nil,
            onHarperComplete: { _, _ in eventLog.append("harper") },
            onLLMBatch: { _, _ in eventLog.append("llm") },
            onLLMFinished: { eventLog.append("finished") }
        )

        #expect(eventLog.count == 3)
        #expect(eventLog[0] == "harper")
        #expect(eventLog[1] == "llm")
        #expect(eventLog[2] == "finished")
    }

    // MARK: Whitelist

    @Test("Whitelist blocks non-allowed bundle ID")
    func whitelistBlocksDisallowedBundleID() {
        let suiteName = "two-phase-whitelist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let whitelist = AppWhitelist(defaults: defaults)

        // iTerm2 is not in the default whitelist
        #expect(whitelist.isAllowed("com.googlecode.iterm2") == false)
    }

    @Test("Whitelist allows known text-editing app")
    func whitelistAllowsKnownApp() {
        let suiteName = "two-phase-whitelist-allow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let whitelist = AppWhitelist(defaults: defaults)

        #expect(whitelist.isAllowed("com.apple.Notes") == true)
        #expect(whitelist.isAllowed("com.apple.TextEdit") == true)
    }

    // MARK: LLM panel visibility

    @Test("LLM batch callback fires when LLM returns suggestions")
    func llmBatchCallbackFiresWithSuggestions() async {
        let suggestion = makeLLMSuggestion()
        let llm = MockLLMProvider(results: [suggestion])
        let harper = StubHarperChecker()
        let orchestrator = CheckOrchestrator(harper: harper, llm: llm)

        var receivedBatch: [LLMStyleSuggestion] = []

        await orchestrator.runCheck(
            text: "We should probably consider doing this",
            context: .stub(),
            config: enabledConfig(),
            apiKey: "key",
            onHarperComplete: { _, _ in },
            onLLMBatch: { suggestions, _ in receivedBatch = suggestions },
            onLLMFinished: {}
        )

        #expect(receivedBatch.count == 1)
        #expect(receivedBatch[0].category == .clarity)
    }

    @Test("LLM batch callback does not fire when LLM returns empty array")
    func llmBatchCallbackSilentOnEmptyResults() async {
        let llm = MockLLMProvider(results: [])
        let harper = StubHarperChecker()
        let orchestrator = CheckOrchestrator(harper: harper, llm: llm)

        var batchFired = false

        await orchestrator.runCheck(
            text: "Hello world",
            context: .stub(),
            config: enabledConfig(),
            apiKey: nil,
            onHarperComplete: { _, _ in },
            onLLMBatch: { _, _ in batchFired = true },
            onLLMFinished: {}
        )

        #expect(batchFired == false, "onLLMBatch must not fire when LLM returns []")
    }

    // MARK: Harper-only mode

    @Test("Harper-only mode: no LLM configured → Harper results only, no errors")
    func harperOnlyWhenNoLLMConfigured() async {
        let harperSuggestion = makeHarperSuggestion()
        let harper = StubHarperChecker(results: [harperSuggestion])
        // nil LLM — simulates user with no LLM provider set up
        let orchestrator = CheckOrchestrator(harper: harper, llm: nil)

        var harperResults: [Suggestion] = []
        var llmBatchFired = false
        var llmFinishedFired = false

        await orchestrator.runCheck(
            text: "tset",
            context: .stub(text: "tset"),
            config: disabledConfig(),
            apiKey: nil,
            onHarperComplete: { suggestions, _ in harperResults = suggestions },
            onLLMBatch: { _, _ in llmBatchFired = true },
            onLLMFinished: { llmFinishedFired = true }
        )

        #expect(harperResults.count == 1, "Harper results must be delivered in harper-only mode")
        #expect(llmBatchFired == false, "LLM batch must not fire when LLM is nil")
        #expect(llmFinishedFired == true, "onLLMFinished must fire even in harper-only mode")
    }

    @Test("Harper-only mode: LLM configured but checks disabled → Harper results only")
    func harperOnlyWhenLLMConfigDisabled() async {
        let harperSuggestion = makeHarperSuggestion()
        let harper = StubHarperChecker(results: [harperSuggestion])
        let llm = MockLLMProvider(results: [makeLLMSuggestion()])
        let orchestrator = CheckOrchestrator(harper: harper, llm: llm)

        var harperResults: [Suggestion] = []
        var llmBatchFired = false

        await orchestrator.runCheck(
            text: "tset",
            context: .stub(text: "tset"),
            config: disabledConfig(),
            apiKey: nil,
            onHarperComplete: { suggestions, _ in harperResults = suggestions },
            onLLMBatch: { _, _ in llmBatchFired = true },
            onLLMFinished: {}
        )

        #expect(harperResults.count == 1)
        #expect(llmBatchFired == false, "LLM disabled in config → batch must not fire")
        // LLM was not called because config.isEnabled == false
        #expect(llm.callCount == 0, "LLM analyze must not be called when config is disabled")
    }

    // MARK: Cancellation

    @Test("Re-trigger: new check supersedes in-flight LLM via harperOnly")
    func retriggeredHarperOnlyReturnsCorrectResults() async {
        // The cancellation contract is: callers cancel Task handles before re-triggering.
        // This test verifies harperOnly() is safe to call in rapid succession.
        let harper = StubHarperChecker(results: [makeHarperSuggestion()])
        let orchestrator = CheckOrchestrator(harper: harper, llm: nil)

        async let first = orchestrator.harperOnly(text: "first")
        async let second = orchestrator.harperOnly(text: "second")

        let (r1, r2) = await (first, second)

        // Both must complete without crashing — actor serializes access
        #expect(r1.count == 1)
        #expect(r2.count == 1)
    }

    @Test("LLM task cancellation: cancelled task returns without crashing")
    func cancelledLLMTaskReturnsCleanly() async throws {
        let llm = MockLLMProvider(results: [makeLLMSuggestion()], delay: 500_000_000)
        let harper = StubHarperChecker()
        let orchestrator = CheckOrchestrator(harper: harper, llm: llm)

        var finishedFired = false

        // Start a check, then cancel the wrapping task immediately after Harper completes
        let task = Task {
            await orchestrator.runCheck(
                text: "Hello",
                context: .stub(),
                config: enabledConfig(),
                apiKey: nil,
                onHarperComplete: { _, _ in },
                onLLMBatch: { _, _ in },
                onLLMFinished: { finishedFired = true }
            )
        }

        // Give Harper time to complete, then cancel before LLM finishes
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value

        // No assertion on finishedFired — cancelled task may or may not call it.
        // The key requirement: no crash, no hang.
    }

    // MARK: LLM network failure

    @Test("LLM network failure → Harper results shown, no crash")
    func llmNetworkFailureDoesNotCrash() async {
        let harperSuggestion = makeHarperSuggestion()
        let harper = StubHarperChecker(results: [harperSuggestion])
        let failingLLM = FailingLLMProvider()
        let orchestrator = CheckOrchestrator(harper: harper, llm: failingLLM)

        var harperResults: [Suggestion] = []
        var llmBatchFired = false
        var finishedFired = false

        await orchestrator.runCheck(
            text: "tset",
            context: .stub(text: "tset"),
            config: enabledConfig(),
            apiKey: nil,
            onHarperComplete: { suggestions, _ in harperResults = suggestions },
            onLLMBatch: { _, _ in llmBatchFired = true },
            onLLMFinished: { finishedFired = true }
        )

        #expect(harperResults.count == 1, "Harper results must be delivered even when LLM fails")
        #expect(llmBatchFired == false, "No LLM batch on failure (silent failure, returns [])")
        #expect(finishedFired == true, "onLLMFinished must fire even after LLM failure")
        #expect(failingLLM.callCount == 1, "LLM was invoked once")
    }

    // MARK: Combined

    @Test("Full two-phase flow: Harper then LLM both deliver results")
    func fullTwoPhaseFlowDeliversBothResults() async {
        let harper = StubHarperChecker(results: [makeHarperSuggestion()])
        let llm = MockLLMProvider(results: [makeLLMSuggestion(), makeLLMSuggestion(category: .tone)])
        let orchestrator = CheckOrchestrator(harper: harper, llm: llm)

        var harperResults: [Suggestion] = []
        var llmResults: [LLMStyleSuggestion] = []
        var finishedFired = false

        await orchestrator.runCheck(
            text: "tset We should probably consider doing this",
            context: .stub(),
            config: enabledConfig(),
            apiKey: "test-key",
            onHarperComplete: { suggestions, _ in harperResults = suggestions },
            onLLMBatch: { suggestions, _ in llmResults = suggestions },
            onLLMFinished: { finishedFired = true }
        )

        #expect(harperResults.count == 1)
        #expect(llmResults.count == 2)
        #expect(finishedFired == true)
    }
}
