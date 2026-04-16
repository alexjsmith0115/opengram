import Foundation

/// DI contract for LLM-based writing suggestions.
/// Mirrors GrammarCheckerProtocol pattern (per D-14).
protocol LLMProviderProtocol: Sendable {
    /// Analyze a paragraph and return 0–3 style suggestions.
    /// Returns empty array on any failure — never throws (D-08 silent failure pattern).
    /// `harperSpans` are the original text spans Harper already flagged; injected into the
    /// system prompt so the LLM avoids duplicating grammar/spelling feedback.
    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion]

    /// Analyze a target paragraph with labeled previous/next context (Phase 16, D-05/D-06).
    /// The LLM is instructed to scope suggestions to `target` only; context paragraphs
    /// are supplied for coherence but not modified. `originalText` on returned
    /// suggestions equals `target` (NFR-7 substring-offset anchor).
    /// Cancellation is driven by the caller's Task.cancel() — no per-actor single-flight.
    func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion]

    /// Verify connectivity to the configured endpoint. Returns true if reachable.
    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool
}
