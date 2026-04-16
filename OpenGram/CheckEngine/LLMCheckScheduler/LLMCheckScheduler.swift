import Foundation
import os.log

/// Incremental LLM check scheduler.
///
/// Split → hash → cache lookup → neighbor-context assembly → per-paragraph LLM fan-out
/// → substring-based offset rebasing → merged `[Suggestion]`. D-01, D-02, D-05, D-07, D-11.
///
/// Plan 16-02 scope: flag-on flow only. Flag-off fallback lands in Plan 16-04; per-paragraph
/// in-flight cancellation map + idle debounce + focus-out trigger land in Plan 16-03.
actor LLMCheckScheduler {

    // MARK: - Dependencies

    private let splitter: any ParagraphSplitting
    private let hasher: any ParagraphHashing
    private let cache: ParagraphSuggestionCache
    private let clock: CacheClock
    private let llm: any LLMProviderProtocol
    private let configProvider: @Sendable () -> LLMConfig
    private let apiKeyProvider: @Sendable () -> String?
    private let incrementalConfig: any IncrementalConfig
    let idleDebounceSeconds: TimeInterval

    private static let logger = Log.logger(for: "LLMCheckScheduler")

    // MARK: - Init

    init(
        splitter: any ParagraphSplitting,
        hasher: any ParagraphHashing,
        cache: ParagraphSuggestionCache,
        clock: CacheClock,
        llm: any LLMProviderProtocol,
        configProvider: @escaping @Sendable () -> LLMConfig,
        apiKeyProvider: @escaping @Sendable () -> String?,
        incrementalConfig: any IncrementalConfig,
        idleDebounceSeconds: TimeInterval = 1.5
    ) {
        self.splitter = splitter
        self.hasher = hasher
        self.cache = cache
        self.clock = clock
        self.llm = llm
        self.configProvider = configProvider
        self.apiKeyProvider = apiKeyProvider
        self.incrementalConfig = incrementalConfig
        self.idleDebounceSeconds = idleDebounceSeconds
    }

    // MARK: - Public API

    /// Split text into paragraphs, reuse cached suggestions for unchanged hashes,
    /// fan out LLM requests for changed/missing paragraphs with neighbor context,
    /// rebase returned style suggestions into source-string index space, merge.
    ///
    /// `harperSpans` preserves Phase 13 LLM-03/LLM-04 duplicate-avoidance contract:
    /// Harper's already-flagged spans are forwarded verbatim to every per-paragraph
    /// LLM call on the flag-on path.
    func check(text: String, bundleID: String, harperSpans: [String] = []) async -> [Suggestion] {
        let paragraphs = splitter.split(text)
        guard !paragraphs.isEmpty else { return [] }

        Self.logger.info("check(bundleID=\(bundleID, privacy: .public), paragraphs=\(paragraphs.count))")

        // Classify every paragraph against the cache.
        var keys: [ParagraphCacheKey] = []
        var cachedSuggestions: [Int: [LLMStyleSuggestion]] = [:]
        var missIndices: [Int] = []

        for paragraph in paragraphs {
            let hash = hasher.hash(paragraph.text)
            let key = ParagraphCacheKey(bundleID: bundleID, paragraphHash: hash)
            keys.append(key)

            if let entry = await cache.lookup(key) {
                switch entry.status {
                case .active:
                    cachedSuggestions[paragraph.index] = entry.suggestions
                case .dismissed:
                    cachedSuggestions[paragraph.index] = []
                case .pending:
                    missIndices.append(paragraph.index)
                }
            } else {
                missIndices.append(paragraph.index)
            }
        }

        // NFR-2 / D-15: neighbor-change staleness is NOT cascaded. If paragraphs[i-1].text changed,
        // paragraphs[i]'s cache entry (indexed by its own hash) stays valid even though its neighbor
        // context is stale. Quality degradation is minor; cascading invalidation defeats caching.

        Self.logger.info("LLM fan-out: \(missIndices.count) requests")

        // Fan out LLM requests for cache-miss paragraphs. Explicit per-paragraph Task spawn
        // (NOT withTaskGroup) — Plan 16-03 promotes this function-local dispatch dictionary
        // to an actor-owned `inFlightByIndex` for per-paragraph cancellation.
        let llmRef = llm
        let cfg = configProvider()
        let apiKey = apiKeyProvider()
        var dispatch: [Int: Task<[LLMStyleSuggestion], Error>] = [:]
        for i in missIndices {
            let paragraph = paragraphs[i]
            let prev: String? = i > 0 ? paragraphs[i - 1].text : nil
            let next: String? = (i + 1) < paragraphs.count ? paragraphs[i + 1].text : nil
            let target = paragraph.text
            let spans = harperSpans
            dispatch[i] = Task<[LLMStyleSuggestion], Error> {
                try Task.checkCancellation()
                return await llmRef.analyze(
                    target: target,
                    previousContext: prev,
                    nextContext: next,
                    config: cfg,
                    apiKey: apiKey,
                    harperSpans: spans
                )
            }
        }

        // Await each Task, upsert into cache (D-11 / FR-9: record attempt even on empty results).
        var llmSuggestions: [Int: [LLMStyleSuggestion]] = [:]
        for (i, task) in dispatch {
            let results = (try? await task.value) ?? []
            llmSuggestions[i] = results
            await cache.upsert(keys[i], status: .active, suggestions: results)
        }

        // Merge cache-hits + fresh LLM results and rebase every paragraph's style suggestions
        // into source-string index space.
        var merged: [Suggestion] = []
        for paragraph in paragraphs {
            let styles = llmSuggestions[paragraph.index] ?? cachedSuggestions[paragraph.index] ?? []
            merged.append(contentsOf: rebase(paragraph: paragraph, styleSuggestions: styles, source: text))
        }
        return merged
    }

    // MARK: - Offset rebasing (NFR-7)

    /// Substring-search `style.originalText` within `paragraph.text`, then map the paragraph-local
    /// range into the SOURCE string's index space. Paragraph.range is the untrimmed source span
    /// (Phase 15 D-03) so we first locate the trimmed body's start by scanning past leading
    /// whitespace/newlines.
    private func rebase(paragraph: Paragraph, styleSuggestions: [LLMStyleSuggestion], source: String) -> [Suggestion] {
        styleSuggestions.compactMap { style in
            guard let local = paragraph.text.range(of: style.originalText) else { return nil }
            let lowerOffset = paragraph.text.distance(from: paragraph.text.startIndex, to: local.lowerBound)
            let upperOffset = paragraph.text.distance(from: paragraph.text.startIndex, to: local.upperBound)
            guard let trimmedStart = source[paragraph.range].firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
                return nil
            }
            let absoluteLower = source.index(trimmedStart, offsetBy: lowerOffset)
            let absoluteUpper = source.index(trimmedStart, offsetBy: upperOffset)
            return Suggestion(
                id: UUID(),
                range: absoluteLower..<absoluteUpper,
                original: style.originalText,
                primaryReplacement: style.revisedText,
                allReplacements: [style.revisedText],
                message: style.explanation,
                category: checkCategory(for: style.category),
                source: .llm,
                priority: UInt8(max(1, min(10, style.confidence)))
            )
        }
    }

    private func checkCategory(for llmCategory: LLMStyleSuggestion.Category) -> CheckCategory {
        switch llmCategory {
        case .clarity: return .clarity
        case .tone: return .tone
        case .rephrase: return .rephrase
        }
    }
}
