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

    /// Runs the full check pipeline: Harper first (immediate callback), then a single
    /// LLM request for style suggestions (separate callback, separate type).
    ///
    /// - Parameters:
    ///   - text: The text to check.
    ///   - context: The TextContext for overlay positioning.
    ///   - config: Current LLM configuration (read from @AppStorage on MainActor, passed here).
    ///   - apiKey: Current API key (read from Keychain on MainActor, passed here).
    ///   - onHarperComplete: Called on MainActor when Harper results are ready.
    ///   - onLLMBatch: Called on MainActor when the LLM request completes.
    ///                 Receives raw LLMStyleSuggestions for display in the LLM panel.
    ///   - onLLMFinished: Called on MainActor when the LLM check has completed (or was skipped).
    func runCheck(
        text: String,
        context: TextContext,
        config: LLMConfig,
        apiKey: String?,
        onHarperComplete: @MainActor @Sendable ([Suggestion], TextContext) -> Void,
        onLLMBatch: @MainActor @Sendable ([LLMStyleSuggestion], TextContext) -> Void,
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

        // 3. Single consolidated LLM request. Task.detached shields from parent cancellation
        // so the request survives hotkey re-fires (D-12, WR-04-gap).
        let styleSuggestions = await Task.detached { [llm] in
            await llm.analyze(paragraph: text, config: config, apiKey: apiKey)
        }.value

        if !styleSuggestions.isEmpty {
            await onLLMBatch(styleSuggestions, context)
        }

        await onLLMFinished()
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
