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

        // Build Harper span strings for the LLM prompt (D-11: soft dedup)
        let harperSpans = harperResults.map { $0.original }
        // Build Harper ranges for hard filtering (D-04, LLM-04)
        let harperRanges = harperResults.map { $0.range }

        // 3. Fire all enabled check types in parallel via TaskGroup (D-12)
        await withTaskGroup(of: [Suggestion].self) { group in
            for checkType in config.enabledChecks {
                group.addTask {
                    await llm.check(
                        text: text, type: checkType, harperSpans: harperSpans,
                        config: config, apiKey: apiKey
                    )
                }
            }
            // Deliver results incrementally as each check type completes (D-01)
            for await llmBatch in group {
                let deduped = Self.hardFilter(llmBatch, harperRanges: harperRanges)
                if !deduped.isEmpty {
                    await onLLMBatch(deduped, context)
                }
            }
        }

        await onLLMFinished()
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
