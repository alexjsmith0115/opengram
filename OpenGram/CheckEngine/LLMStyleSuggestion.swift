import Foundation

/// Paragraph-level writing suggestion from the LLM.
/// Distinct from `Suggestion` (which is range-based for overlay rendering).
/// Used by the consolidated LLM service to carry style feedback before
/// range resolution and overlay mapping.
struct LLMStyleSuggestion: Sendable {

    enum Category: String, Sendable, CaseIterable {
        case clarity
        case tone
        case rephrase

        /// Maps to the overlay-rendering CheckCategory used by the legacy Suggestion type.
        /// Phase 12 will replace this bridge once CheckOrchestrator adopts the new LLM panel flow.
        var checkCategory: CheckCategory {
            switch self {
            case .clarity: return .clarity
            case .tone: return .tone
            case .rephrase: return .rephrase
            }
        }
    }

    let category: Category
    let originalText: String
    let revisedText: String
    let explanation: String
    /// Confidence score 1–10 as reported by the LLM. Only suggestions >= 7 are surfaced.
    let confidence: Int
}
