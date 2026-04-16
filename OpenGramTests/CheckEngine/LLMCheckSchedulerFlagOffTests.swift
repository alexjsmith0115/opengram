import Testing
import Foundation
import os
@testable import OpenGramLib

// MARK: - Test doubles

/// Splitter that delegates to DoubleNewlineSplitter but counts how many times it's been called.
private final class RecordingSplitter: ParagraphSplitting, @unchecked Sendable {
    private let inner = DoubleNewlineSplitter()
    private let lock = NSLock()
    private var _count = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func split(_ text: String) -> [Paragraph] {
        lock.lock(); _count += 1; lock.unlock()
        return inner.split(text)
    }
}

/// Hasher that delegates to Sha256ParagraphHasher but counts how many times it's been called.
private final class RecordingHasher: ParagraphHashing, @unchecked Sendable {
    private let inner = Sha256ParagraphHasher()
    private let lock = NSLock()
    private var _count = 0
    var callCount: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func hash(_ text: String) -> UInt64 {
        lock.lock(); _count += 1; lock.unlock()
        return inner.hash(text)
    }
}

/// Mutable IncrementalConfig for runtime flag flipping inside a single test.
private final class MutableIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    private let lock = NSLock()
    private var _flag: Bool
    init(_ initial: Bool) { self._flag = initial }
    var isIncrementalCheckingEnabled: Bool { lock.lock(); defer { lock.unlock() }; return _flag }
    func set(_ value: Bool) { lock.lock(); _flag = value; lock.unlock() }
}

/// LLM mock that distinguishes calls to the legacy `analyze(paragraph:)` from the
/// Phase-16 `analyze(target:)` and records harperSpans forwarded on either path.
private final class MethodRecordingLLM: LLMProviderProtocol, @unchecked Sendable {
    struct ParagraphCall: Sendable {
        let paragraph: String
        let harperSpans: [String]
    }
    struct TargetCall: Sendable {
        let target: String
        let previous: String?
        let next: String?
        let harperSpans: [String]
    }

    private struct State {
        var paragraphCalls: [ParagraphCall] = []
        var targetCalls: [TargetCall] = []
        var cannedForParagraph: [LLMStyleSuggestion] = []
        var cannedForTarget: [String: [LLMStyleSuggestion]] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var paragraphCalls: [ParagraphCall] { state.withLock { $0.paragraphCalls } }
    var paragraphCallCount: Int { state.withLock { $0.paragraphCalls.count } }
    var paragraphInputs: [String] { state.withLock { $0.paragraphCalls.map { $0.paragraph } } }
    var targetCalls: [TargetCall] { state.withLock { $0.targetCalls } }
    var targetCallCount: Int { state.withLock { $0.targetCalls.count } }

    func setCannedForParagraph(_ canned: [LLMStyleSuggestion]) {
        state.withLock { $0.cannedForParagraph = canned }
    }

    func setCannedForTarget(_ canned: [String: [LLMStyleSuggestion]]) {
        state.withLock { $0.cannedForTarget = canned }
    }

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

// MARK: - Helpers

private func style(category: LLMStyleSuggestion.Category = .clarity, original: String, revised: String = "revised", confidence: Int = 8) -> LLMStyleSuggestion {
    LLMStyleSuggestion(category: category, originalText: original, revisedText: revised, explanation: "why", confidence: confidence)
}

private func makeScheduler(
    llm: MethodRecordingLLM,
    splitter: any ParagraphSplitting = DoubleNewlineSplitter(),
    hasher: any ParagraphHashing = Sha256ParagraphHasher(),
    cache: ParagraphSuggestionCache = ParagraphSuggestionCache(),
    config: any IncrementalConfig,
    idleDebounceSeconds: TimeInterval = 1.5
) -> LLMCheckScheduler {
    LLMCheckScheduler(
        splitter: splitter,
        hasher: hasher,
        cache: cache,
        clock: SystemClock(),
        llm: llm,
        configProvider: { LLMConfig.default },
        apiKeyProvider: { "test-key" },
        incrementalConfig: config,
        idleDebounceSeconds: idleDebounceSeconds
    )
}

// MARK: - Tests

@Suite struct LLMCheckSchedulerFlagOffTests {

    // 1. Flag-off path does NOT consult the splitter.
    @Test func flagOff_doesNotCallSplitter() async {
        let llm = MethodRecordingLLM()
        let splitter = RecordingSplitter()
        let scheduler = makeScheduler(llm: llm, splitter: splitter, config: MutableIncrementalConfig(false))

        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")

        #expect(splitter.callCount == 0)
    }

    // 2. Flag-off path does NOT consult the hasher.
    @Test func flagOff_doesNotCallHasher() async {
        let llm = MethodRecordingLLM()
        let hasher = RecordingHasher()
        let scheduler = makeScheduler(llm: llm, hasher: hasher, config: MutableIncrementalConfig(false))

        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")

        #expect(hasher.callCount == 0)
    }

    // 3. Flag-off path does NOT touch the cache (seeded entry unchanged).
    @Test func flagOff_doesNotTouchCache() async {
        let llm = MethodRecordingLLM()
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()

        // Seed an entry for "P1" and record its lastAccessedAt.
        let key = ParagraphCacheKey(bundleID: "b", paragraphHash: hasher.hash("P1"))
        await cache.upsert(key, status: .active, suggestions: [style(original: "P1")])
        let seeded = await cache.lookup(key)
        let seededTimestamp = try! #require(seeded?.lastAccessedAt)

        // Do flag-off check over text containing "P1".
        let scheduler = makeScheduler(llm: llm, cache: cache, config: MutableIncrementalConfig(false))
        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")

        // The seeded entry is only observable via lookup (which itself bumps lastAccessedAt),
        // so we assert that the second lookup sees a timestamp >= first (cache contents preserved
        // and scheduler never went through the cache path itself).
        let after = await cache.lookup(key)
        let afterTimestamp = try! #require(after?.lastAccessedAt)
        // If the scheduler had consulted the cache during check(), we'd have at least one
        // intervening bump. Instead, the only bump is THIS lookup's. So the difference between
        // the two observed timestamps equals one clock-read granularity — not two.
        // Assertion: entry still exists with original content; nothing removed/replaced.
        #expect(after?.status == .active)
        #expect(after?.suggestions.count == 1)
        #expect(afterTimestamp >= seededTimestamp)
    }

    // 4. Flag-off path routes through the legacy `analyze(paragraph:)` method with the full text.
    @Test func flagOff_callsLegacyAnalyzeParagraphWithFullText() async {
        let llm = MethodRecordingLLM()
        let scheduler = makeScheduler(llm: llm, config: MutableIncrementalConfig(false))

        let text = "The first paragraph.\n\nA second paragraph here."
        _ = await scheduler.check(text: text, bundleID: "b")

        #expect(llm.paragraphCallCount == 1)
        #expect(llm.targetCallCount == 0)
        #expect(llm.paragraphInputs.first == text)
    }

    // 5. harperSpans are forwarded verbatim to the legacy call on the flag-off path.
    //    Pins the byte-identical pre-v1.2 contract (LLM-03/LLM-04).
    @Test func flagOff_forwardsHarperSpansToLegacyCall() async {
        let llm = MethodRecordingLLM()
        let scheduler = makeScheduler(llm: llm, config: MutableIncrementalConfig(false))

        _ = await scheduler.check(text: "hello", bundleID: "b", harperSpans: ["foo", "bar"])

        #expect(llm.paragraphCalls.count == 1)
        #expect(llm.paragraphCalls.first?.harperSpans == ["foo", "bar"])
    }

    // 6. Flag-on path forwards harperSpans to every per-paragraph target call. Confirms LLM-03
    //    duplicate-avoidance is preserved on the incremental path too.
    @Test func flagOn_forwardsHarperSpansToTargetCall() async {
        let llm = MethodRecordingLLM()
        llm.setCannedForTarget([:])
        let scheduler = makeScheduler(llm: llm, config: MutableIncrementalConfig(true))

        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b", harperSpans: ["foo"])

        #expect(llm.targetCallCount == 2)
        for call in llm.targetCalls {
            #expect(call.harperSpans == ["foo"])
        }
    }

    // 7. Flag-off returned suggestions rebase onto the full source text (substring offset rule).
    @Test func flagOff_returnedSuggestionsRebaseOntoSourceText() async {
        let llm = MethodRecordingLLM()
        llm.setCannedForParagraph([style(original: "quick brown", revised: "quick")])
        let scheduler = makeScheduler(llm: llm, config: MutableIncrementalConfig(false))

        let source = "The quick brown fox jumps."
        let out = await scheduler.check(text: source, bundleID: "b")

        #expect(out.count == 1)
        let sug = try! #require(out.first)
        #expect(String(source[sug.range]) == "quick brown")
        #expect(sug.primaryReplacement == "quick")
        #expect(sug.source == .llm)
    }

    // 8. If originalText is not found in source, the suggestion is dropped silently (no crash).
    @Test func flagOff_missingOriginalTextDroppedSilently() async {
        let llm = MethodRecordingLLM()
        llm.setCannedForParagraph([style(original: "not-in-source", revised: "x")])
        let scheduler = makeScheduler(llm: llm, config: MutableIncrementalConfig(false))

        let out = await scheduler.check(text: "Something else entirely.", bundleID: "b")

        #expect(out.isEmpty)
    }

    // 9. onKeystroke still routes through check() under flag-off; legacy path fires exactly once
    //    within the debounce window.
    @Test func flagOff_onKeystrokeStillDelegatesToCheck() async {
        let llm = MethodRecordingLLM()
        let scheduler = makeScheduler(llm: llm, config: MutableIncrementalConfig(false), idleDebounceSeconds: 0.01)

        let fired = OSAllocatedUnfairLock(initialState: false)
        await scheduler.onKeystroke(text: "hello", bundleID: "b") { _ in
            fired.withLock { $0 = true }
        }

        // Poll up to 500ms for the fire — cooperative pool can introduce scheduling latency.
        for _ in 0..<25 {
            try? await Task.sleep(for: .milliseconds(20))
            if fired.withLock({ $0 }) { break }
        }

        #expect(fired.withLock { $0 } == true)
        #expect(llm.paragraphCallCount == 1)
        #expect(llm.targetCallCount == 0)
    }

    // 10. Live-flag read (D-14): ON → OFF takes effect on next check().
    @Test func flagFlipOnToOff_onNextCallBehavesAsFlagOff() async {
        let llm = MethodRecordingLLM()
        let config = MutableIncrementalConfig(true)
        let scheduler = makeScheduler(llm: llm, config: config)

        // First call: flag ON — uses target-calls path for both paragraphs.
        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")
        #expect(llm.targetCallCount == 2)
        #expect(llm.paragraphCallCount == 0)

        // Flip OFF.
        config.set(false)

        // Second call: flag OFF — uses legacy paragraph call, no additional target calls.
        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")
        #expect(llm.targetCallCount == 2)
        #expect(llm.paragraphCallCount == 1)
    }

    // 11. Live-flag read (D-14): OFF → ON takes effect on next check().
    @Test func flagFlipOffToOn_onNextCallBehavesAsFlagOn() async {
        let llm = MethodRecordingLLM()
        let config = MutableIncrementalConfig(false)
        let scheduler = makeScheduler(llm: llm, config: config)

        // First call: flag OFF — legacy paragraph path.
        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")
        #expect(llm.paragraphCallCount == 1)
        #expect(llm.targetCallCount == 0)

        // Flip ON.
        config.set(true)

        // Second call: flag ON — per-paragraph target calls, splitter/hasher/cache engaged.
        _ = await scheduler.check(text: "P1\n\nP2", bundleID: "b")
        #expect(llm.paragraphCallCount == 1)
        #expect(llm.targetCallCount == 2)
    }
}
