import Foundation

/// Which LLM check to run. Each type uses a different system prompt.
enum LLMCheckType: String, Sendable, CaseIterable, Codable {
    case tone
    case clarity
    case rephrase

    var checkCategory: CheckCategory {
        switch self {
        case .tone: return .tone
        case .clarity: return .clarity
        case .rephrase: return .rephrase
        }
    }
}

/// A single suggestion returned by the LLM, before offset resolution.
struct LLMSuggestionDTO: Codable, Sendable {
    let original: String
    let replacement: String
    let reason: String
    let category: String
}

/// DI contract for LLM-based writing suggestions.
/// Mirrors GrammarCheckerProtocol pattern (per D-14).
protocol LLMProviderProtocol: Sendable {
    /// Run a specific check type against the provided text.
    /// The harperSpans parameter contains text ranges already flagged by Harper,
    /// included in the system prompt so the LLM skips them (D-11).
    /// Returns zero or more suggestions. Never throws -- returns empty on failure (D-08).
    func check(text: String, type: LLMCheckType, harperSpans: [String], config: LLMConfig, apiKey: String?) async -> [Suggestion]

    /// Verify connectivity to the configured endpoint. Returns true if reachable.
    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool
}
