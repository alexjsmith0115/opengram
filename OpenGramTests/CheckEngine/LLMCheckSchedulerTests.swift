import Testing
import Foundation
import os
@testable import OpenGramLib

// MARK: - Test doubles

private final class RecordingLLM: LLMProviderProtocol, @unchecked Sendable {
    struct Call: Sendable {
        let target: String
        let previous: String?
        let next: String?
        let harperSpans: [String]
    }
    private struct State {
        var calls: [Call] = []
        var cannedByTarget: [String: [LLMStyleSuggestion]] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var calls: [Call] { state.withLock { $0.calls } }
    var callCount: Int { calls.count }

    func setCanned(_ canned: [String: [LLMStyleSuggestion]]) {
        state.withLock { $0.cannedByTarget = canned }
    }

    func resetCalls() {
        state.withLock { $0.calls.removeAll() }
    }

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        []
    }

    func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        state.withLock {
            $0.calls.append(Call(target: target, previous: previousContext, next: nextContext, harperSpans: harperSpans))
            return $0.cannedByTarget[target] ?? []
        }
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
}

private struct AlwaysOnIncrementalConfig: IncrementalConfig {
    var isIncrementalCheckingEnabled: Bool { true }
    var minIssueCount: Int { 2 }
    var minWordCount: Int { 12 }
    var idleDebounceSeconds: TimeInterval { 1.5 }
}

private final class SchedulerFakeClock: CacheClock, @unchecked Sendable {
    var current: Date
    init(_ seed: Date = Date(timeIntervalSince1970: 0)) { self.current = seed }
    func now() -> Date { current }
}

private func makeScheduler(
    llm: RecordingLLM,
    cache: ParagraphSuggestionCache = ParagraphSuggestionCache()
) -> LLMCheckScheduler {
    LLMCheckScheduler(
        splitter: DoubleNewlineSplitter(),
        hasher: Sha256ParagraphHasher(),
        cache: cache,
        clock: SystemClock(),
        llm: llm,
        configProvider: { LLMConfig.default },
        apiKeyProvider: { "test-key" },
        incrementalConfig: AlwaysOnIncrementalConfig()
    )
}

private func style(category: LLMStyleSuggestion.Category = .clarity, original: String, revised: String = "revised", confidence: Int = 8) -> LLMStyleSuggestion {
    LLMStyleSuggestion(category: category, originalText: original, revisedText: revised, explanation: "why", confidence: confidence)
}

// MARK: - Tests

@Suite struct LLMCheckSchedulerTests {

    @Test func check_emptyText_returnsEmpty_noLLMCalls() async {
        let llm = RecordingLLM()
        let scheduler = makeScheduler(llm: llm)
        let out = await scheduler.check(text: "", bundleID: "com.test")
        #expect(out.isEmpty)
        #expect(llm.callCount == 0)
    }

    @Test func check_coldCache_firesOneRequestPerParagraph_withNeighborContext() async {
        let llm = RecordingLLM()
        llm.setCanned([
            "P1": [style(original: "P1")],
            "P2": [style(original: "P2")],
            "P3": [style(original: "P3")]
        ])
        let scheduler = makeScheduler(llm: llm)
        let text = "P1\n\nP2\n\nP3"
        let out = await scheduler.check(text: text, bundleID: "b")

        #expect(llm.callCount == 3)
        let callsByTarget = Dictionary(uniqueKeysWithValues: llm.calls.map { ($0.target, $0) })

        let c1 = try! #require(callsByTarget["P1"])
        #expect(c1.previous == nil)
        #expect(c1.next == "P2")

        let c2 = try! #require(callsByTarget["P2"])
        #expect(c2.previous == "P1")
        #expect(c2.next == "P3")

        let c3 = try! #require(callsByTarget["P3"])
        #expect(c3.previous == "P2")
        #expect(c3.next == nil)

        #expect(out.count == 3)
        for s in out { #expect(s.source == .llm) }
    }

    @Test func check_warmCacheAllActive_issuesZeroLLMCalls() async {
        let llm = RecordingLLM()
        llm.setCanned(["P1": [style(original: "P1")], "P2": [style(original: "P2")]])
        let scheduler = makeScheduler(llm: llm)
        let text = "P1\n\nP2"

        _ = await scheduler.check(text: text, bundleID: "b")
        #expect(llm.callCount == 2)

        llm.resetCalls()
        let out = await scheduler.check(text: text, bundleID: "b")
        #expect(llm.callCount == 0)
        #expect(out.count == 2)
    }

    @Test func check_warmCacheMixedDismissed_noSuggestionsFromDismissed_noReissue() async {
        let llm = RecordingLLM()
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()

        let text = "P1\n\nP2"
        let h0 = hasher.hash("P1")
        let h1 = hasher.hash("P2")
        let k0 = ParagraphCacheKey(bundleID: "b", paragraphHash: h0)
        let k1 = ParagraphCacheKey(bundleID: "b", paragraphHash: h1)
        await cache.upsert(k0, status: .active, suggestions: [style(original: "P1")])
        await cache.upsert(k1, status: .dismissed, suggestions: [style(original: "P2"), style(original: "P2-b", revised: "r2")])

        let scheduler = makeScheduler(llm: llm, cache: cache)
        let out = await scheduler.check(text: text, bundleID: "b")
        #expect(llm.callCount == 0)
        #expect(out.count == 1)
    }

    @Test func check_offsetRebasing_suggestionRangesAnchoredInSource() async {
        let llm = RecordingLLM()
        llm.setCanned([
            "The quick brown fox.": [style(original: "quick brown", revised: "quick")]
        ])
        let scheduler = makeScheduler(llm: llm)
        let source = "Intro.\n\nThe quick brown fox.\n\nOutro."
        let out = await scheduler.check(text: source, bundleID: "b")
        #expect(out.count == 1)
        let sug = try! #require(out.first)
        #expect(String(source[sug.range]) == "quick brown")
        #expect(sug.original == "quick brown")
        #expect(sug.primaryReplacement == "quick")
    }

    @Test func check_neighborChangeNoCascadeInvalidation() async {
        let llm = RecordingLLM()
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()

        // Seed P2's cache entry as active with a known suggestion.
        let p2Hash = hasher.hash("P2")
        let p2Key = ParagraphCacheKey(bundleID: "b", paragraphHash: p2Hash)
        let cachedSug = style(original: "P2", revised: "P2-rev")
        await cache.upsert(p2Key, status: .active, suggestions: [cachedSug])

        llm.setCanned(["P1-edited": [style(original: "P1-edited")]])
        let scheduler = makeScheduler(llm: llm, cache: cache)

        // P1 is a NEW (edited) paragraph — cache miss. P2 unchanged — cache hit.
        let out = await scheduler.check(text: "P1-edited\n\nP2", bundleID: "b")
        #expect(llm.callCount == 1)
        #expect(llm.calls.first?.target == "P1-edited")

        // Returned suggestions should contain P2's cached content unchanged (as revised text).
        let p2Returned = out.first(where: { $0.primaryReplacement == "P2-rev" })
        #expect(p2Returned != nil)
    }

    @Test func check_doesNotBlockMainThread_runsOnCooperativePool() async {
        let llm = RecordingLLM()
        llm.setCanned(["P1": [style(original: "P1")]])
        let scheduler = makeScheduler(llm: llm)

        let result = await Task.detached { () -> Int in
            let out = await scheduler.check(text: "P1\n\nP2", bundleID: "b")
            return out.count
        }.value
        // Compile-and-run verification: scheduler callable off MainActor from detached context.
        #expect(result >= 1)
    }

    @Test func check_cacheUpsertRecordsActiveOnLLMCall() async {
        let llm = RecordingLLM()
        llm.setCanned(["P1": [style(original: "P1")]])
        let cache = ParagraphSuggestionCache()
        let scheduler = makeScheduler(llm: llm, cache: cache)

        _ = await scheduler.check(text: "P1", bundleID: "b")

        let hasher = Sha256ParagraphHasher()
        let key = ParagraphCacheKey(bundleID: "b", paragraphHash: hasher.hash("P1"))
        let entry = await cache.lookup(key)
        #expect(entry?.status == .active)
    }

    @Test func check_performanceUnder50ms_for100paragraphs_ciVarianceCeiling() async {
        let llm = RecordingLLM()
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()
        let text = (0..<100).map { "p\($0)" }.joined(separator: "\n\n")

        // Warm cache: all 100 paragraphs seeded as .active with empty suggestions.
        for i in 0..<100 {
            let key = ParagraphCacheKey(bundleID: "b", paragraphHash: hasher.hash("p\(i)"))
            await cache.upsert(key, status: .active, suggestions: [])
        }

        let scheduler = makeScheduler(llm: llm, cache: cache)
        // Warm-up call
        _ = await scheduler.check(text: text, bundleID: "b")
        #expect(llm.callCount == 0)

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            _ = await scheduler.check(text: text, bundleID: "b")
        }
        #expect(elapsed < .milliseconds(50))
    }

    // WR-04: Unicode ZWJ emoji sequence must not crash rebase() and must round-trip
    // to a source range whose substring equals style.originalText.
    @Test func rebase_zwjEmojiParagraph_producesAlignedSourceRange() async {
        let llm = RecordingLLM()
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}"
        let target = "Hello \(family) world"
        llm.setCanned([target: [style(original: family, revised: "[family]")]])
        let scheduler = makeScheduler(llm: llm)

        let out = await scheduler.check(text: target, bundleID: "b")
        #expect(out.count == 1)
        guard let s = out.first else { return }
        #expect(String(target[s.range]) == family)
    }
}
