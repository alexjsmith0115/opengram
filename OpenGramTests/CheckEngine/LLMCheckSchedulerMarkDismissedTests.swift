import Testing
import Foundation
@testable import OpenGramLib

@Suite("LLMCheckScheduler.markDismissed")
struct LLMCheckSchedulerMarkDismissedTests {

    private struct OnIncrementalConfig: IncrementalConfig {
        var minIssueCount: Int { 2 }
        var minWordCount: Int { 12 }
        var idleDebounceSeconds: TimeInterval { 1.5 }
    }

    @Test func markDismissed_populatesCacheWithDismissedStatus() async {
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()
        let paragraphText = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu."
        let hash = hasher.hash(paragraphText)
        let key = ParagraphCacheKey(bundleID: "com.example", paragraphHash: hash)
        await cache.upsert(key, status: .active, suggestions: [
            LLMStyleSuggestion(category: .clarity, originalText: "Alpha", revisedText: "Alfa", explanation: "", confidence: 8)
        ])

        let scheduler = makeScheduler(cache: cache)
        await scheduler.markDismissed(bundleID: "com.example", hash: hash)
        let entry = await cache.lookup(key)
        #expect(entry?.status == .dismissed)
    }

    @Test func markDismissed_noOp_whenNoEntry() async {
        let cache = ParagraphSuggestionCache()
        let scheduler = makeScheduler(cache: cache)
        await scheduler.markDismissed(bundleID: "com.example", hash: 12345)
        let entry = await cache.lookup(ParagraphCacheKey(bundleID: "com.example", paragraphHash: 12345))
        #expect(entry == nil)
    }

    @Test func dismissedEntry_returnsZeroSuggestions_onNextCheck() async {
        let cache = ParagraphSuggestionCache()
        let hasher = Sha256ParagraphHasher()
        let paragraphText = "Alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu."
        let hash = hasher.hash(paragraphText)
        let key = ParagraphCacheKey(bundleID: "com.example", paragraphHash: hash)
        await cache.upsert(key, status: .active, suggestions: [
            LLMStyleSuggestion(category: .clarity, originalText: "Alpha", revisedText: "Alfa", explanation: "", confidence: 8)
        ])

        let scheduler = makeScheduler(cache: cache, hasher: hasher)
        await scheduler.markDismissed(bundleID: "com.example", hash: hash)

        let suggestions = await scheduler.check(text: paragraphText, bundleID: "com.example")
        #expect(suggestions.isEmpty)
    }

    private func makeScheduler(
        cache: ParagraphSuggestionCache,
        hasher: any ParagraphHashing = Sha256ParagraphHasher()
    ) -> LLMCheckScheduler {
        LLMCheckScheduler(
            splitter: DoubleNewlineSplitter(),
            hasher: hasher,
            cache: cache,
            clock: SystemClock(),
            llm: StubLLM(),
            configProvider: { .default },
            apiKeyProvider: { nil },
            incrementalConfig: OnIncrementalConfig()
        )
    }

    private struct StubLLM: LLMProviderProtocol {
        func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }
        func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }
        func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
    }
}
