import Foundation

/// Top-level JSON response from the LLM for paragraph-level style checking.
/// Wraps an array of `SuggestionDTO` objects decoded from the assistant message content.
struct LLMResponseDTO: Codable, Sendable {

    let suggestions: [SuggestionDTO]

    struct SuggestionDTO: Codable, Sendable {
        let category: String
        // swiftlint:disable:next identifier_name
        let revised_text: String
        let explanation: String
        let confidence: Int

        enum CodingKeys: String, CodingKey {
            case category
            case revised_text
            case explanation
            case confidence
        }

        /// Maps this DTO to a `LLMStyleSuggestion`, or returns nil if:
        /// - `category` is not a recognised `LLMStyleSuggestion.Category`
        /// - `confidence` is below 7
        func toModel(originalText: String) -> LLMStyleSuggestion? {
            guard confidence >= 7 else { return nil }
            guard let resolvedCategory = LLMStyleSuggestion.Category(rawValue: category) else { return nil }
            return LLMStyleSuggestion(
                category: resolvedCategory,
                originalText: originalText,
                revisedText: revised_text,
                explanation: explanation,
                confidence: confidence
            )
        }
    }

    /// Decodes `data` as an `LLMResponseDTO` and maps valid suggestions to `LLMStyleSuggestion`.
    /// Suggestions with confidence < 7 or unknown categories are silently dropped.
    /// Throws if `data` is not valid JSON matching the expected schema.
    static func toModels(from data: Data, originalText: String) throws -> [LLMStyleSuggestion] {
        let dto = try JSONDecoder().decode(LLMResponseDTO.self, from: data)
        return dto.suggestions.compactMap { $0.toModel(originalText: originalText) }
    }
}
