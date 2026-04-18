import Foundation

/// Phase 20 state-machine actor. See CONTEXT.md §State Machine, §Reconciliation, §Cache Eviction.
///
/// Owns:
///   - `cache: [ParagraphHash: ParagraphCacheEntry]` — one source of truth for paragraph state
///   - `currentSet: [String: ParagraphSet]` — last-known live set per bundleID
///   - `eventContinuation` — broadcasts `.suggestionsChanged` on every cache/set mutation
///
/// Consumers: TextMonitor (Plan 08) drives via `reconcile` + `invalidateDisplayed`;
/// OverlayController (Plan 09) subscribes to `events` and reads `renderableSuggestions`.
actor ParagraphSuggestionStore: LLMRequestQueueStore {

    // MARK: - State

    private var cache: [ParagraphHash: ParagraphCacheEntry] = [:]
    private var currentSet: [String: ParagraphSet] = [:]

    // MARK: - Dependencies

    private let queue: LLMRequestQueue
    private let splitter: ParagraphSplitter
    private let config: OpenGramConfig
    private let clock: any CacheClock
    private let textProvider: @Sendable (String) -> String?
    private let versionProvider: @Sendable (String) -> String?

    // MARK: - Events

    private let eventContinuation: AsyncStream<StoreEvent>.Continuation
    nonisolated let events: AsyncStream<StoreEvent>

    // MARK: - Init

    init(
        queue: LLMRequestQueue,
        splitter: ParagraphSplitter,
        config: OpenGramConfig = OpenGramConfig(),
        clock: any CacheClock = SystemClock(),
        textProvider: @Sendable @escaping (String) -> String?,
        versionProvider: @Sendable @escaping (String) -> String? = { _ in nil }
    ) {
        let (stream, cont) = AsyncStream.makeStream(of: StoreEvent.self)
        self.events = stream
        self.eventContinuation = cont
        self.queue = queue
        self.splitter = splitter
        self.config = config
        self.clock = clock
        self.textProvider = textProvider
        self.versionProvider = versionProvider
    }

    // MARK: - Reconcile (PLL-03, PLL-06, PLL-07, PLL-08, PLL-14)

    func reconcile(set: ParagraphSet) async {
        currentSet[set.bundleID] = set
        let setHashes = Set(set.paragraphs.map(\.hash))

        // 1. Sweep — only entries in this bundle; other bundles untouched (PLL-08b).
        for (hash, entry) in cache
            where hash.bundleID == set.bundleID && !setHashes.contains(hash)
        {
            if case .pending = entry.state {
                await queue.cancel(hash: hash)
            }
            cache[hash] = nil
        }

        // 2. Submit misses (respecting caret skip, minParagraphLength, minWordCount).
        let minLen = config.minParagraphLength
        let minWords = config.minParagraphWordCount
        for entry in set.paragraphs {
            if entry.hash == set.caretParagraphHash { continue }                 // PLL-06
            if entry.text.count < minLen { continue }
            let wordCount = entry.text.split(whereSeparator: { $0.isWhitespace }).count
            if wordCount < minWords { continue }
            if cache[entry.hash] != nil { continue }                             // PLL-03b/c, PLL-14

            cache[entry.hash] = ParagraphCacheEntry(
                hash: entry.hash,
                originalText: entry.text,
                state: .pending(submittedAt: clock.now())
            )
            await queue.submit(hash: entry.hash, paragraph: entry.text, bundleID: set.bundleID)
        }

        eventContinuation.yield(.suggestionsChanged(bundleID: set.bundleID))
    }

    // MARK: - Invalidate displayed (PLL-04)

    func invalidateDisplayed(bundleID: String, currentSet set: ParagraphSet) {
        currentSet[bundleID] = set
        eventContinuation.yield(.suggestionsChanged(bundleID: bundleID))
    }

    // MARK: - Queue callback (LLMRequestQueueStore) — PLL-05

    func handleQueueResponse(
        hash: ParagraphHash,
        bundleID: String,
        result: Result<[LLMStyleSuggestion], Error>
    ) async {
        guard cache[hash] != nil else { return }

        // Verify-on-response: re-read current text, re-split, check hash still present.
        if let currentText = textProvider(bundleID) {
            let version = versionProvider(bundleID)
            let reSet = splitter.split(
                text: currentText,
                bundleID: bundleID,
                version: version,
                caretOffset: nil
            )
            if !reSet.paragraphs.contains(where: { $0.hash == hash }) {
                cache[hash] = nil
                eventContinuation.yield(.suggestionsChanged(bundleID: bundleID))
                return
            }
        } else {
            // Text provider returned nil — element lost focus or AX failed; drop.
            cache[hash] = nil
            eventContinuation.yield(.suggestionsChanged(bundleID: bundleID))
            return
        }

        switch result {
        case .success(let styles):
            if let suggestion = Self.mapToSuggestion(
                styles: styles,
                hash: hash,
                originalText: cache[hash]!.originalText
            ) {
                cache[hash]!.state = .ready(suggestion)
            } else {
                cache[hash]!.state = .readyEmpty
            }
        case .failure(let error):
            cache[hash]!.state = .failed(error)
        }
        eventContinuation.yield(.suggestionsChanged(bundleID: bundleID))
    }

    // MARK: - User transitions

    func markDismissed(hash: ParagraphHash) {
        guard cache[hash] != nil else { return }
        cache[hash]!.state = .dismissed
        eventContinuation.yield(.suggestionsChanged(bundleID: hash.bundleID))
    }

    func markAccepted(hash: ParagraphHash) {
        guard cache[hash] != nil else { return }
        cache[hash]!.state = .accepted
        eventContinuation.yield(.suggestionsChanged(bundleID: hash.bundleID))
    }

    // MARK: - Render surface (PLL-08a preservation + PLL-13 merge point)

    func renderableSuggestions(for bundleID: String) -> [Suggestion] {
        guard let set = currentSet[bundleID] else { return [] }
        let setHashes = Set(set.paragraphs.map(\.hash))
        return cache.values.compactMap { entry in
            guard setHashes.contains(entry.hash) else { return nil }
            guard case .ready(let sug) = entry.state else { return nil }
            return sug
        }
    }

    // MARK: - Test inspection seams

    func _cacheEntryKind(hash: ParagraphHash) -> ParagraphSuggestionState.Kind? {
        cache[hash]?.state.kind
    }

    func _cacheCount() -> Int { cache.count }

    func _cacheCount(bundleID: String) -> Int {
        cache.keys.filter { $0.bundleID == bundleID }.count
    }

    // MARK: - Mapping

    /// Picks the first `LLMStyleSuggestion` whose revised text differs from original
    /// and builds a single paragraph-level `Suggestion`. Returns nil when no usable
    /// rewrite — caller transitions to `.readyEmpty`.
    ///
    /// Range placeholder: covers the whole `originalText`. Plan 09 re-resolves against the
    /// CURRENT live text at render time (Pitfall #3 — never trust cached String.Index
    /// across mutations).
    static func mapToSuggestion(
        styles: [LLMStyleSuggestion],
        hash: ParagraphHash,
        originalText: String
    ) -> Suggestion? {
        let usable = styles.first { s in
            !s.revisedText.isEmpty && s.revisedText != s.originalText
        } ?? styles.first
        guard let pick = usable, !pick.revisedText.isEmpty else { return nil }

        let category: CheckCategory
        switch pick.category {
        case .tone:     category = .tone
        case .clarity:  category = .clarity
        case .rephrase: category = .rephrase
        }

        // Placeholder range covers the entire originalText. Plan 09 rebuilds the
        // real range against live AX text before rendering.
        let range = originalText.startIndex..<originalText.endIndex

        return Suggestion(
            id: UUID(),
            range: range,
            original: originalText,
            primaryReplacement: pick.revisedText,
            allReplacements: [pick.revisedText],
            message: pick.explanation,
            category: category,
            source: .llm,
            priority: UInt8(max(0, min(255, pick.confidence))),
            paragraphHash: hash.sha256Prefix8UInt64
        )
    }
}

// MARK: - UInt64 compression helper for Plan 06 → Plan 07 transition

extension ParagraphHash {
    /// Temporary compatibility shim: compresses first 8 hex bytes into UInt64 so this
    /// plan compiles against the existing `Suggestion.paragraphHash: UInt64?`. Plan 07
    /// deletes this helper AND flips the Suggestion field to `ParagraphHash?` in one
    /// atomic change.
    var sha256Prefix8UInt64: UInt64 {
        var result: UInt64 = 0
        var count = 0
        var idx = sha256.startIndex
        while idx < sha256.endIndex && count < 16 {
            let byteEnd = sha256.index(idx, offsetBy: 2, limitedBy: sha256.endIndex) ?? sha256.endIndex
            if byteEnd > idx, let byte = UInt64(sha256[idx..<byteEnd], radix: 16) {
                result = (result << 8) | (byte & 0xFF)
            }
            idx = byteEnd
            count += 2
        }
        return result
    }
}
