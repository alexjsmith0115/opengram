import Foundation
import os.log

/// Incremental LLM check scheduler.
///
/// Split → hash → cache lookup → neighbor-context assembly → per-paragraph LLM fan-out
/// → substring-based offset rebasing → merged `[Suggestion]`. D-01, D-02, D-05, D-07, D-11.
///
/// Includes per-paragraph in-flight cancellation map (`inFlightByIndex`),
/// keystroke idle-debounce (`onKeystroke` + `pendingIdleTask`), and focus-loss trigger
/// (`checkOnFocusLoss`).
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

    // D-03, D-04: per-paragraph cancellation. Keyed on paragraph index -- index is stable for the
    // duration of one check() invocation's paragraph layout; hash would collide across position changes.
    private var inFlightByIndex: [Int: Task<[LLMStyleSuggestion], Error>] = [:]

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
        incrementalConfig: any IncrementalConfig
    ) {
        self.splitter = splitter
        self.hasher = hasher
        self.cache = cache
        self.clock = clock
        self.llm = llm
        self.configProvider = configProvider
        self.apiKeyProvider = apiKeyProvider
        self.incrementalConfig = incrementalConfig
    }

    // MARK: - Public API

    /// Split text into paragraphs, reuse cached suggestions for unchanged hashes,
    /// fan out LLM requests for changed/missing paragraphs with neighbor context,
    /// rebase returned style suggestions into source-string index space, merge.
    ///
    /// `harperSpans` preserves LLM-03/LLM-04 duplicate-avoidance contract:
    /// Harper's already-flagged spans are forwarded verbatim to every per-paragraph
    /// LLM call on the flag-on path.
    func check(text: String, bundleID: String, harperSpans: [String] = []) async -> [Suggestion] {
        Self.logger.info("scheduler.check entry — textLen=\(text.count) bundleID=\(bundleID, privacy: .public)")
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

        // Fan out LLM requests for cache-miss paragraphs. Explicit per-paragraph Task spawn;
        // tasks tracked in actor-owned `inFlightByIndex` so a subsequent check() call can
        // cancel prior in-flight work at the same index before replacing it.
        let llmRef = llm
        let cfg = configProvider()
        let apiKey = apiKeyProvider()

        // D-04: cancel-before-replace. Any prior Task at one of the indices we're about to
        // re-dispatch is cancelled so its URLSession work stops before the replacement fires.
        for i in missIndices {
            inFlightByIndex[i]?.cancel()
        }

        // Snapshot the tasks THIS invocation spawned so a concurrently-entered check() call
        // replacing `inFlightByIndex[i]` after our own cancel-before-replace doesn't make us
        // read its task or clear its entry. Each invocation only clears its own entries.
        var ownTasks: [Int: Task<[LLMStyleSuggestion], Error>] = [:]
        for i in missIndices {
            let paragraph = paragraphs[i]
            let prev: String? = i > 0 ? paragraphs[i - 1].text : nil
            let next: String? = (i + 1) < paragraphs.count ? paragraphs[i + 1].text : nil
            let target = paragraph.text
            let spans = harperSpans
            let task = Task<[LLMStyleSuggestion], Error> {
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
            inFlightByIndex[i] = task
            ownTasks[i] = task
        }

        // Await each Task, upsert into cache (D-11 / FR-9: record attempt even on empty results).
        // CR-01: distinguish cancellation from empty LLM result — never poison the cache with []
        // on cancel. CR-02: the cache.upsert must live inside the same "still own the slot" guard
        // so a peer's fresh result isn't clobbered by our trailing write.
        var llmSuggestions: [Int: [LLMStyleSuggestion]] = [:]
        for i in missIndices {
            guard let task = ownTasks[i] else { continue }
            let results: [LLMStyleSuggestion]
            let taskCancelled: Bool
            do {
                results = try await task.value
                taskCancelled = false
            } catch is CancellationError {
                results = []
                taskCancelled = true
            } catch {
                results = []
                taskCancelled = false
            }
            llmSuggestions[i] = results
            let stillOwnsSlot = (inFlightByIndex[i] == task)
            if stillOwnsSlot {
                inFlightByIndex[i] = nil
            }
            if !taskCancelled, stillOwnsSlot {
                await cache.upsert(keys[i], status: .active, suggestions: results)
            }
        }

        // Merge cache-hits + fresh LLM results and rebase every paragraph's style suggestions
        // into source-string index space.
        var merged: [Suggestion] = []
        for paragraph in paragraphs {
            let styles = llmSuggestions[paragraph.index] ?? cachedSuggestions[paragraph.index] ?? []
            let hash = ParagraphHash(bundleID: bundleID, paragraphText: paragraph.text)
            merged.append(contentsOf: rebase(paragraph: paragraph, paragraphHash: hash, styleSuggestions: styles, source: text))
        }
        return merged
    }

    // MARK: - Offset rebasing (NFR-7)

    /// Search `style.originalText` directly within the trimmed source slice for `paragraph.range`.
    /// Paragraph.range is the untrimmed source span (D-03), so we advance past leading
    /// whitespace/newlines first. Avoids the paragraph.text→source Character-offset translation,
    /// which can misalign on Unicode sequences where paragraph.text normalization differs from
    /// source[paragraph.range] (WR-04).
    private func rebase(paragraph: Paragraph, paragraphHash: ParagraphHash, styleSuggestions: [LLMStyleSuggestion], source: String) -> [Suggestion] {
        styleSuggestions.compactMap { style in
            guard let trimmedStart = source[paragraph.range].firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) else {
                return nil
            }
            let bodySlice = source[trimmedStart..<paragraph.range.upperBound]
            guard let sourceRange = bodySlice.range(of: style.originalText) else { return nil }
            return Suggestion(
                id: UUID(),
                range: sourceRange,
                original: style.originalText,
                primaryReplacement: style.revisedText,
                allReplacements: [style.revisedText],
                message: style.explanation,
                category: checkCategory(for: style.category),
                source: .llm,
                priority: UInt8(max(1, min(10, style.confidence))),
                paragraphHash: paragraphHash
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

    // MARK: - Scheduling entry points (D-09, D-10)

    // D-09: idle-debounce. On each keystroke signal, cancel prior pending task and spawn a
    // replacement. When the sleep completes uncancelled, fire check() and hand results to
    // onComplete (fire-and-forget; callers wanting an awaitable result use check() directly).
    //
    // Cancellation semantic: DELIVERY-GATING, not request-cancelling. Cancelling
    // `pendingIdleTask` only prevents the pre-sleep debounce fire and the post-check
    // `onComplete` callback — per-paragraph fan-out Tasks spawned inside `check()` are
    // unstructured and do NOT inherit cancellation from this wrapper. In-flight HTTP
    // traffic at the moment of cancellation continues to completion; its results either
    // land in the paragraph cache (next warm-cache lookup benefits) or are dropped by
    // the stale-ownership guard in the await loop. Cross-invocation cancellation of
    // fan-out work is handled by `check()` itself via `inFlightByIndex[i]?.cancel()`
    // when a later call re-dispatches the same index.
    private var pendingIdleTask: Task<Void, Never>?

    func onKeystroke(text: String, bundleID: String, harperSpans: [String] = [], onComplete: @escaping @Sendable ([Suggestion]) -> Void) {
        pendingIdleTask?.cancel()
        // SET-10 / D-03: live-read per-call so Advanced tab Stepper changes take effect on next keystroke.
        // Mirrors flag-read pattern — no cached snapshot.
        let debounce = incrementalConfig.idleDebounceSeconds
        pendingIdleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(debounce))
            if Task.isCancelled { return }
            guard let self else { return }
            let suggestions = await self.check(text: text, bundleID: bundleID, harperSpans: harperSpans)
            if Task.isCancelled { return }
            onComplete(suggestions)
        }
    }

    // D-10: focus-loss trigger reuses the main check() flow with no idle wait. Cancels any
    // pending debounce fire so the two signals don't double-fire.
    func checkOnFocusLoss(text: String, bundleID: String, harperSpans: [String] = []) async -> [Suggestion] {
        pendingIdleTask?.cancel()
        pendingIdleTask = nil
        return await check(text: text, bundleID: bundleID, harperSpans: harperSpans)
    }

    /// Card Dismiss action entry point (D-17).
    /// Thin wrapper around `cache.markDismissed(...)` so the UI layer never touches the cache directly.
    /// No-op when no entry exists for the key (mirrors cache.markDismissed semantics).
    func markDismissed(bundleID: String, hash: UInt64) async {
        await cache.markDismissed(ParagraphCacheKey(bundleID: bundleID, paragraphHash: hash))
    }
}
