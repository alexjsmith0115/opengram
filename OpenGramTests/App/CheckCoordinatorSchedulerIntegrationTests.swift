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

/// Runtime-flippable incremental config for testing ON→OFF transitions.
private final class MutableIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    private let lock = NSLock()
    private var _flag: Bool
    init(_ initial: Bool) { self._flag = initial }
    var isIncrementalCheckingEnabled: Bool { lock.lock(); defer { lock.unlock() }; return _flag }
    func set(_ value: Bool) { lock.lock(); _flag = value; lock.unlock() }
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
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig(true))

        let text = "P1\n\nP2\n\nP3"

        _ = await scheduler.check(text: text, bundleID: "com.test")
        #expect(llm.targetCallCount == 3)

        _ = await scheduler.check(text: text, bundleID: "com.test")
        #expect(llm.targetCallCount == 3)
    }

    // 2. Flag-off path: identical repeated checks each fire one legacy full-text call (no cache).
    @Test func flagOffPath_twoIdenticalChecks_bothIssueFullTextLLMCall() async {
        let llm = RecordingLLM()
        let cache = ParagraphSuggestionCache()
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig(false))

        let text = "P1\n\nP2"

        _ = await scheduler.check(text: text, bundleID: "com.test")
        _ = await scheduler.check(text: text, bundleID: "com.test")

        #expect(llm.paragraphCallCount == 2)
        #expect(llm.targetCallCount == 0)
    }

    // 3. Mid-stream flag flip ON→OFF: cache contents survive, but OFF path does not consult them.
    @Test func flagFlipMidStream_onToOff_cacheRemainsButUnused() async {
        let llm = RecordingLLM()
        llm.setCannedForTarget(["P1": [style(original: "P1")]])
        let cache = ParagraphSuggestionCache()
        let config = MutableIncrementalConfig(true)
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: config)

        // Warm cache under flag-on.
        _ = await scheduler.check(text: "P1", bundleID: "com.test")
        #expect(llm.targetCallCount == 1)

        // Capture the seeded entry's lastAccessedAt.
        let hasher = Sha256ParagraphHasher()
        let key = ParagraphCacheKey(bundleID: "com.test", paragraphHash: hasher.hash("P1"))
        let seeded = await cache.lookup(key)
        let seededTimestamp = try! #require(seeded?.lastAccessedAt)

        // Flip OFF.
        config.set(false)

        // Check under OFF path — fires legacy paragraph call; does NOT consult cache.
        _ = await scheduler.check(text: "P1", bundleID: "com.test")
        #expect(llm.paragraphCallCount == 1)
        #expect(llm.targetCallCount == 1)

        // Cache entry still present (dormant, not cleared).
        let after = await cache.lookup(key)
        #expect(after?.status == .active)
        #expect(after?.suggestions.count == 1)
        // The two observed timestamps differ only because this lookup bumped lastAccessedAt — not
        // because the scheduler consulted the cache during the OFF-path check.
        let afterTimestamp = try! #require(after?.lastAccessedAt)
        #expect(afterTimestamp >= seededTimestamp)
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
        let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig(true))

        let text = "P1\n\nP2"
        _ = await scheduler.check(text: text, bundleID: "A")
        _ = await scheduler.check(text: text, bundleID: "B")

        // 2 paragraphs × 2 bundles = 4 analyze calls. No cache-hit reuse across bundles.
        #expect(llm.targetCallCount == 4)
    }

    // 5. harperSpans preserved end-to-end through the scheduler on both feature-flag paths.
    //    Closes Phase 13 LLM-03/LLM-04 regression risk.
    @Test func integration_harperSpansPreservedThroughScheduler() async {
        // Flag OFF: one legacy paragraph call sees harperSpans verbatim.
        do {
            let llm = RecordingLLM()
            let cache = ParagraphSuggestionCache()
            let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig(false))

            _ = await scheduler.check(text: "P1\n\nP2", bundleID: "com.test", harperSpans: ["foo"])

            #expect(llm.paragraphCallCount == 1)
            #expect(llm.paragraphCalls.first?.harperSpans == ["foo"])
        }

        // Flag ON: every per-paragraph target call sees the same harperSpans array.
        do {
            let llm = RecordingLLM()
            let cache = ParagraphSuggestionCache()
            let scheduler = makeIntegrationScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig(true))

            _ = await scheduler.check(text: "P1\n\nP2", bundleID: "com.test", harperSpans: ["foo"])

            #expect(llm.targetCallCount == 2)
            for call in llm.targetCalls {
                #expect(call.harperSpans == ["foo"])
            }
        }
    }
}
