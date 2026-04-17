import Testing
import Foundation
import os
@testable import OpenGramLib

// MARK: - Test doubles

/// Records every LLM call (both legacy paragraph and per-target paths) with harperSpans.
/// Cache/splitter/hasher are real — this mock is the ONLY layer below the scheduler in this suite.
private final class RecordingLLM: LLMProviderProtocol, @unchecked Sendable {
    struct ParagraphCall: Sendable { let paragraph: String; let harperSpans: [String] }
    struct TargetCall: Sendable { let target: String; let previous: String?; let next: String?; let harperSpans: [String] }

    private struct State {
        var paragraphCalls: [ParagraphCall] = []
        var targetCalls: [TargetCall] = []
        var cannedForParagraph: [LLMStyleSuggestion] = []
        var cannedForTarget: [String: [LLMStyleSuggestion]] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var paragraphCalls: [ParagraphCall] { state.withLock { $0.paragraphCalls } }
    var paragraphCallCount: Int { state.withLock { $0.paragraphCalls.count } }
    var targetCalls: [TargetCall] { state.withLock { $0.targetCalls } }
    var targetCallCount: Int { state.withLock { $0.targetCalls.count } }

    func setCannedForParagraph(_ canned: [LLMStyleSuggestion]) { state.withLock { $0.cannedForParagraph = canned } }
    func setCannedForTarget(_ canned: [String: [LLMStyleSuggestion]]) { state.withLock { $0.cannedForTarget = canned } }
    func reset() { state.withLock { $0.paragraphCalls.removeAll(); $0.targetCalls.removeAll() } }

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        state.withLock {
            $0.paragraphCalls.append(ParagraphCall(paragraph: paragraph, harperSpans: harperSpans))
            return $0.cannedForParagraph
        }
    }

    func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        state.withLock {
            $0.targetCalls.append(TargetCall(target: target, previous: previousContext, next: nextContext, harperSpans: harperSpans))
            return $0.cannedForTarget[target] ?? []
        }
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
}

/// Incremental config holding Phase 17 Advanced-tab tunables
/// (minIssueCount / minWordCount / idleDebounceSeconds).
private final class MutableIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    private let lock = NSLock()
    private var _minIssueCount: Int
    private var _minWordCount: Int
    private var _idleDebounceSeconds: TimeInterval
    init(
        minIssueCount: Int = 2,
        minWordCount: Int = 12,
        idleDebounceSeconds: TimeInterval = 1.5
    ) {
        self._minIssueCount = minIssueCount
        self._minWordCount = minWordCount
        self._idleDebounceSeconds = idleDebounceSeconds
    }
    var minIssueCount: Int { lock.lock(); defer { lock.unlock() }; return _minIssueCount }
    var minWordCount: Int { lock.lock(); defer { lock.unlock() }; return _minWordCount }
    var idleDebounceSeconds: TimeInterval { lock.lock(); defer { lock.unlock() }; return _idleDebounceSeconds }
    func setIdleDebounceSeconds(_ value: TimeInterval) { lock.lock(); _idleDebounceSeconds = value; lock.unlock() }
    func setMinIssueCount(_ value: Int) { lock.lock(); _minIssueCount = value; lock.unlock() }
    func setMinWordCount(_ value: Int) { lock.lock(); _minWordCount = value; lock.unlock() }
}

// MARK: - Helpers

private func style(original: String, revised: String = "revised", confidence: Int = 8) -> LLMStyleSuggestion {
    LLMStyleSuggestion(category: .clarity, originalText: original, revisedText: revised, explanation: "why", confidence: confidence)
}

/// Builds a scheduler with real Phase 15 components (no mocks below the scheduler).
private func makeIntegrationScheduler(
    llm: RecordingLLM,
    cache: ParagraphSuggestionCache,
    config: any IncrementalConfig
) -> LLMCheckScheduler {
    LLMCheckScheduler(
        splitter: DoubleNewlineSplitter(),
        hasher: Sha256ParagraphHasher(),
        cache: cache,
        clock: SystemClock(),
        llm: llm,
        configProvider: { LLMConfig.default },
        apiKeyProvider: { "test-key" },
        incrementalConfig: config
    )
}

// MARK: - Tests

@Suite struct CheckCoordinatorSchedulerIntegrationTests {

    // 1. Incremental path: identical repeated checks issue zero new LLM calls after the cache warms.
    //    Direct evidence for ROADMAP success criterion 1.
    @Test func incrementalPath_twoIdenticalChecks_secondIssuesZeroLLMCalls() async {
        let llm = RecordingLLM()
        llm.setCannedForTarget([
            "P1": [style(original: "P1")],
            "P2": [style(original: "P2")],
            "P3": [style(original: "P3")]
        ])
        let cache = ParagraphSuggestionCache()
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig())

        let text = "P1\n\nP2\n\nP3"

        _ = await scheduler.check(text: text, bundleID: "com.test")
        #expect(llm.targetCallCount == 3)

        _ = await scheduler.check(text: text, bundleID: "com.test")
        #expect(llm.targetCallCount == 3)
    }

    // 4. INCR-06: cache is scoped per bundleID. Same text under a different bundleID is a full
    //    cache miss — no cross-bundle contamination.
    @Test func realCacheAcrossBundleIDs_scopedCorrectly() async {
        let llm = RecordingLLM()
        llm.setCannedForTarget([
            "P1": [style(original: "P1")],
            "P2": [style(original: "P2")]
        ])
        let cache = ParagraphSuggestionCache()
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig())

        let text = "P1\n\nP2"
        _ = await scheduler.check(text: text, bundleID: "A")
        _ = await scheduler.check(text: text, bundleID: "B")

        // 2 paragraphs × 2 bundles = 4 analyze calls. No cache-hit reuse across bundles.
        #expect(llm.targetCallCount == 4)
    }

    // 5. harperSpans preserved end-to-end through the scheduler.
    //    Closes Phase 13 LLM-03/LLM-04 regression risk.
    @Test func integration_harperSpansPreservedThroughScheduler() async {
        let llm = RecordingLLM()
        let cache = ParagraphSuggestionCache()
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig())

        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "com.test", harperSpans: ["foo"])

        #expect(llm.targetCallCount == 2)
        for call in llm.targetCalls {
            #expect(call.harperSpans == ["foo"])
        }
    }
}
