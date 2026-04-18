import Foundation
import os.log

/// Orchestrates the Harper checking pipeline. Delivers incremental updates to the UI
/// via callbacks (D-01, D-02). Paragraph-level LLM checks run event-driven via
/// ParagraphSuggestionStore (D-04) — not here.
actor CheckOrchestrator {

    private let harper: any GrammarCheckerProtocol
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "CheckOrchestrator"
    )

    init(harper: any GrammarCheckerProtocol) {
        self.harper = harper
    }

    /// Runs Harper and delivers results via `onHarperComplete`. `onLLMFinished` is called
    /// immediately after to signal the debounce cycle is done (TextMonitor compatibility).
    ///
    /// - Parameters:
    ///   - text: The text to check.
    ///   - context: The TextContext for overlay positioning.
    ///   - onHarperComplete: Called on MainActor when Harper results are ready.
    ///   - onLLMFinished: Called on MainActor after the check cycle completes.
    func runCheck(
        text: String,
        context: TextContext,
        onHarperComplete: @MainActor @Sendable ([Suggestion], TextContext) -> Void,
        onLLMFinished: @MainActor @Sendable () -> Void
    ) async {
        let harperResults = await harper.check(text: text)
        await onHarperComplete(harperResults, context)
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
