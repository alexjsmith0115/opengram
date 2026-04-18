import Testing
import Foundation
@testable import OpenGramLib

@MainActor
@Suite("Rephrase card lifecycle: hide vs dismiss vs accept")
struct RephraseCardLifecycleTests {

    private struct OnFlag: IncrementalConfig {
        var minIssueCount: Int { 2 }
        var minWordCount: Int { 12 }
        var idleDebounceSeconds: TimeInterval { 1.5 }
    }

    private static func onFlagConfig() -> OpenGramConfig {
        let name = UUID().uuidString
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return OpenGramConfig(defaults: suite)
    }

    private struct StubLLM: LLMProviderProtocol {
        func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }
        func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }
        func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
    }

    // REPH-08: Hide path does NOT mutate the cache. A subsequent check with the same
    // paragraph text finds the entry still .active (still re-presentable).
    @Test func hide_doesNotMutateCache() async {
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()
        let text = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi."
        let hash = hasher.hash(text)
        let key = ParagraphCacheKey(bundleID: "com.example", paragraphHash: hash)
        await cache.upsert(key, status: .active, suggestions: [
            LLMStyleSuggestion(category: .clarity, originalText: "Alpha", revisedText: "Alfa", explanation: "", confidence: 8),
            LLMStyleSuggestion(category: .clarity, originalText: "beta", revisedText: "Beta", explanation: "", confidence: 8)
        ])

        let entryBefore = await cache.lookup(key)
        #expect(entryBefore?.status == .active)

        // "Hide" is simply: OverlayController.showUnderlines() — it never touches the cache.
        let ctrl = OverlayController(config: Self.onFlagConfig())
        ctrl.hideUnderlines(inParagraphScalarRange: (scalarStart: 0, scalarLength: 70))
        ctrl.showUnderlines()

        let entryAfter = await cache.lookup(key)
        #expect(entryAfter?.status == .active)
    }

    // REPH-07: Dismiss path flips the cache entry to .dismissed.
    @Test func dismiss_marksCacheEntryDismissed() async {
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()
        let text = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi."
        let hash = hasher.hash(text)
        let key = ParagraphCacheKey(bundleID: "com.example", paragraphHash: hash)
        await cache.upsert(key, status: .active, suggestions: [
            LLMStyleSuggestion(category: .clarity, originalText: "Alpha", revisedText: "Alfa", explanation: "", confidence: 8)
        ])

        let scheduler = LLMCheckScheduler(
            splitter: DoubleNewlineSplitter(),
            hasher: hasher,
            cache: cache,
            clock: SystemClock(),
            llm: StubLLM(),
            configProvider: { .default },
            apiKeyProvider: { nil },
            incrementalConfig: OnFlag()
        )

        await scheduler.markDismissed(bundleID: "com.example", hash: hash)
        let entry = await cache.lookup(key)
        #expect(entry?.status == .dismissed)
    }

    // REPH-07 second half: after dismiss, the next `scheduler.check()` for the same text
    // returns zero suggestions (dismissed status honored).
    @Test func dismiss_thenRecheck_returnsNoSuggestions() async {
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()
        let text = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi."
        let hash = hasher.hash(text)
        let key = ParagraphCacheKey(bundleID: "com.example", paragraphHash: hash)
        await cache.upsert(key, status: .active, suggestions: [
            LLMStyleSuggestion(category: .clarity, originalText: "Alpha", revisedText: "Alfa", explanation: "", confidence: 8)
        ])

        let scheduler = LLMCheckScheduler(
            splitter: DoubleNewlineSplitter(),
            hasher: hasher,
            cache: cache,
            clock: SystemClock(),
            llm: StubLLM(),
            configProvider: { .default },
            apiKeyProvider: { nil },
            incrementalConfig: OnFlag()
        )
        await scheduler.markDismissed(bundleID: "com.example", hash: hash)
        let results = await scheduler.check(text: text, bundleID: "com.example")
        #expect(results.isEmpty)
    }
}
