import Testing
@testable import OpenGramLib
import Foundation

@MainActor
@Suite("RewriteWindowViewModel")
struct RewriteWindowViewModelTests {

    // MARK: - Stubs

    private final class StubLLM: RewriteLLMProvider {
        let handler: @Sendable (String, RewriteTone) async throws -> String
        init(_ handler: @escaping @Sendable (String, RewriteTone) async throws -> String) {
            self.handler = handler
        }
        func rewrite(text: String, tone: RewriteTone) async throws -> String {
            try await handler(text, tone)
        }
    }

    private struct StubConfig: RewriteConfigProvider {
        var llmConfig: LLMConfig
        var apiKey: String?
        func currentAPIKey() -> String? { apiKey }
    }

    // MARK: - Factory

    private func makeVM(
        original: String = "hello world",
        apiKey: String? = "sk-test",
        rewriteHandler: @escaping @Sendable (String, RewriteTone) async throws -> String
    ) -> RewriteWindowViewModel {
        let llm = StubLLM(rewriteHandler)
        let config = LLMConfig(
            baseURL: "http://localhost:1234/v1",
            model: "test-model",
            enabledChecks: [.tone, .rephrase],
            temperature: 0.3,
            maxTokens: 512,
            requestTimeout: 30,
            confidenceThreshold: LLMConfig.defaultConfidenceThreshold
        )
        let configMgr = StubConfig(llmConfig: config, apiKey: apiKey)
        return RewriteWindowViewModel(original: original, llm: llm, configManager: configMgr)
    }

    // MARK: - Tests

    @Test("Initial state is idle, no tone, empty revised, canApply false")
    func initialState() {
        let vm = makeVM { _, _ in "result" }
        #expect(vm.status == .idle)
        #expect(vm.selectedTone == nil)
        #expect(vm.revised == "")
        #expect(vm.canApply == false)
    }

    @Test("selectTone moves status idle->loading->done and stores raw revised")
    func happyPath() async {
        let raw = "  Hi  "
        let vm = makeVM { _, _ in raw }
        vm.selectTone(.friendly)
        await vm.waitForCompletion()
        #expect(vm.status == .done)
        #expect(vm.revised == raw)
        #expect(vm.selectedTone == .friendly)
        #expect(vm.canApply == true)
    }

    @Test("Stale response from older generation is discarded")
    func staleResponseDropped() async {
        let vm = makeVM { _, tone in
            if tone == .friendly {
                try await Task.sleep(nanoseconds: 80_000_000)
                return "first"
            }
            return "second"
        }
        vm.selectTone(.friendly)
        // Immediately supersede with a faster call
        vm.selectTone(.professional)
        await vm.waitForCompletion()
        #expect(vm.revised == "second")
        #expect(vm.selectedTone == .professional)
    }

    @Test("Editing original after .done invalidates the rewrite")
    func editInvalidates() async {
        let vm = makeVM { _, _ in "done result" }
        vm.selectTone(.simple)
        await vm.waitForCompletion()
        #expect(vm.status == .done)

        vm.updateOriginal("different text")
        #expect(vm.status == .idle)
        #expect(vm.revised == "")
        #expect(vm.selectedTone == nil)
        #expect(vm.canApply == false)
    }

    @Test("LLMRewriteError.emptyResponse surfaces .llmFailed and pins attemptedTone")
    func emptyResponseError() async {
        let vm = makeVM { _, _ in throw LLMRewriteError.emptyResponse }
        vm.selectTone(.friendly)
        await vm.waitForCompletion()

        guard case .error(let err, let tone) = vm.status,
              case .llmFailed = err else {
            Issue.record("Expected .error(.llmFailed, ...)")
            return
        }
        #expect(tone == .friendly)
        #expect(vm.canApply == false)
    }

    @Test("Missing API key still fires LLM (local LLMs need no key)")
    func missingAPIKeyStillFires() async {
        let vm = makeVM(apiKey: nil) { _, tone in
            #expect(tone == .professional)
            return "rewritten"
        }
        vm.selectTone(.professional)
        await vm.waitForCompletion()

        #expect(vm.status == .done)
        #expect(vm.revised == "rewritten")
    }

    @Test("retry replays the failed tone, not any later selection")
    func retryPinned() async {
        final class State: @unchecked Sendable {
            var callCount = 0
            var lastTone: RewriteTone?
        }
        let state = State()
        let vm = makeVM { _, tone in
            state.callCount += 1
            state.lastTone = tone
            if state.callCount == 1 { throw LLMRewriteError.emptyResponse }
            return "retried"
        }

        vm.selectTone(.friendly)
        await vm.waitForCompletion()
        guard case .error = vm.status else {
            Issue.record("Expected error after first call")
            return
        }
        #expect(state.lastTone == .friendly)

        vm.retry()
        await vm.waitForCompletion()
        #expect(state.callCount == 2)
        #expect(state.lastTone == .friendly)
        #expect(vm.status == .done)
        #expect(vm.revised == "retried")
    }

    @Test("cancel() halts the in-flight task")
    func cancelHalts() async throws {
        let vm = makeVM { _, _ in
            try await Task.sleep(nanoseconds: 200_000_000)
            return "result"
        }
        vm.selectTone(.simple)
        vm.cancel()
        // Give the cancelled task time to fully exit
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(vm.revised != "result")
        #expect(vm.status != .done)
    }

    @Test("setError(_:attemptedTone:) updates status without firing LLM")
    func setErrorDirect() {
        let vm = makeVM { _, _ in Issue.record("LLM should not be called"); return "x" }
        vm.setError(.targetChanged, attemptedTone: nil)
        guard case .error(let err, let tone) = vm.status,
              case .targetChanged = err else {
            Issue.record("Expected .error(.targetChanged, ...)")
            return
        }
        #expect(tone == nil)
    }
}
