import Foundation

/// Paragraph-level writing suggestion from the LLM.
/// Distinct from `Suggestion` (which is range-based for overlay rendering).
/// Used by the consolidated LLM service to carry style feedback before
/// range resolution and overlay mapping.
struct LLMStyleSuggestion: Sendable, Equatable, Hashable {

    enum Category: String, Sendable, CaseIterable {
        case clarity
        case tone
        case rephrase
    }

    let category: Category
    let originalText: String
    let revisedText: String
    let explanation: String
    /// Confidence score 1–10 as reported by the LLM. Only suggestions >= 7 are surfaced.
    let confidence: Int
}
