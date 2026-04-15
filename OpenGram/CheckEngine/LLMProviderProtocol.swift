import Foundation

/// DI contract for LLM-based writing suggestions.
/// Mirrors GrammarCheckerProtocol pattern (per D-14).
protocol LLMProviderProtocol: Sendable {
    /// Analyze a paragraph and return 0–3 style suggestions.
    /// Returns empty array on any failure — never throws (D-08 silent failure pattern).
    func analyze(paragraph: String, config: LLMConfig, apiKey: String?) async -> [LLMStyleSuggestion]

    /// Verify connectivity to the configured endpoint. Returns true if reachable.
    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool
}
