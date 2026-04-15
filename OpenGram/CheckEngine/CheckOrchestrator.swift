import Foundation
import os.log

/// Orchestrates the two-tier checking pipeline: Harper (instant, deterministic) followed
/// by optional LLM checks (async, subjective). Owns the merged suggestion state and
/// delivers incremental updates to the UI via callbacks (D-01, D-02).
actor CheckOrchestrator {

    private let harper: any GrammarCheckerProtocol
    private let llm: (any LLMProviderProtocol)?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "CheckOrchestrator"
    )

    init(harper: any GrammarCheckerProtocol, llm: (any LLMProviderProtocol)?) {
        self.harper = harper
        self.llm = llm
    }

    /// Runs the full check pipeline: Harper first (immediate callback), then LLM checks
    /// in parallel (incremental callbacks as each completes).
    ///
    /// - Parameters:
    ///   - text: The text to check.
    ///   - context: The TextContext for overlay positioning.
    ///   - config: Current LLM configuration (read from @AppStorage on MainActor, passed here).
    ///   - apiKey: Current API key (read from Keychain on MainActor, passed here).
    ///   - onHarperComplete: Called on MainActor when Harper results are ready.
    ///   - onLLMBatch: Called on MainActor each time an LLM check type returns results.
    ///                 Receives the NEW batch only (caller accumulates).
    ///   - onLLMFinished: Called on MainActor when all LLM checks have completed (or were skipped).
    func runCheck(
        text: String,
        context: TextContext,
        config: LLMConfig,
        apiKey: String?,
        onHarperComplete: @MainActor @Sendable ([Suggestion], TextContext) -> Void,
        onLLMBatch: @MainActor @Sendable ([Suggestion], TextContext) -> Void,
        onLLMFinished: @MainActor @Sendable () -> Void
    ) async {
        // 1. Harper runs first — synchronous from actor perspective
        let harperResults = await harper.check(text: text)
        await onHarperComplete(harperResults, context)

        // 2. LLM checks if configured (D-07: guard on isEnabled)
        guard let llm, config.isEnabled else {
            await onLLMFinished()
            return
        }

        // Build Harper ranges for hard filtering (D-04, LLM-04)
        let harperRanges = harperResults.map { $0.range }

        // 3. Single consolidated LLM request (Phase 09 refactor).
        // Task.detached shields from parent cancellation so the request survives
        // hotkey re-fires (D-12, WR-04-gap).
        let (stream, continuation) = AsyncStream<[Suggestion]>.makeStream()

        let detachedTask = Task.detached { [llm] in
            let styleSuggestions = await llm.analyze(paragraph: text, config: config, apiKey: apiKey)
            let suggestions = Self.mapStyleSuggestions(styleSuggestions, sourceText: text)
            continuation.yield(suggestions)
            continuation.finish()
        }

        // Deliver results when the single LLM request completes (D-01)
        for await llmBatch in stream {
            let deduped = Self.hardFilter(llmBatch, harperRanges: harperRanges)
            if !deduped.isEmpty {
                await onLLMBatch(deduped, context)
            }
        }

        _ = await detachedTask.value

        await onLLMFinished()
    }

    /// Maps paragraph-level LLMStyleSuggestions to range-based Suggestions by searching for
    /// the originalText in sourceText (D-16 pattern). Suggestions whose originalText is not
    /// found are dropped. Phase 12 will replace this with the new LLM panel flow.
    nonisolated static func mapStyleSuggestions(
        _ styleSuggestions: [LLMStyleSuggestion],
        sourceText: String
    ) -> [Suggestion] {
        var searchStart = sourceText.startIndex
        var results: [Suggestion] = []
        for style in styleSuggestions {
            guard let range = sourceText.range(of: style.originalText, range: searchStart..<sourceText.endIndex) else {
                continue
            }
            results.append(Suggestion(
                id: UUID(),
                range: range,
                original: style.originalText,
                primaryReplacement: style.revisedText,
                allReplacements: [style.revisedText],
                message: style.explanation,
                category: style.category.checkCategory,
                source: .llm,
                priority: 50
            ))
            searchStart = range.upperBound
        }
        return results
    }

    /// Hard-filters LLM suggestions that overlap any Harper-flagged range (D-04, LLM-04).
    /// An LLM suggestion overlaps if its range intersects (not just touches) a Harper range.
    nonisolated static func hardFilter(
        _ llmSuggestions: [Suggestion],
        harperRanges: [Range<String.Index>]
    ) -> [Suggestion] {
        llmSuggestions.filter { suggestion in
            !harperRanges.contains { harperRange in
                suggestion.range.overlaps(harperRange)
            }
        }
    }

    // MARK: - Harper passthrough (for TextMonitor compatibility)

    /// Convenience for callers that only need Harper (e.g., when LLM is not configured).
    func harperOnly(text: String) async -> [Suggestion] {
        await harper.check(text: text)
    }

    /// Forwards addToDictionary to Harper.
    func addToDictionary(word: String) async {
        await harper.addToDictionary(word: word)
    }
}
