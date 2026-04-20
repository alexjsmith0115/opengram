import Testing
import Foundation
@testable import OpenGramLib

@Suite struct LLMResponseDTOTests {

    // MARK: - Valid JSON

    @Test func parsesValidTwoSuggestionResponse() throws {
        let json = """
        {
            "suggestions": [
                {"category": "tone", "revised_text": "Consider this", "explanation": "Hedge", "confidence": 9},
                {"category": "rephrase", "revised_text": "Rewrite it", "explanation": "Flow", "confidence": 7}
            ]
        }
        """
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "original")
        #expect(suggestions.count == 2)
        #expect(suggestions[0].category == .tone)
        #expect(suggestions[0].revisedText == "Consider this")
        #expect(suggestions[1].category == .rephrase)
    }

    @Test func parsesEmptySuggestionsArrayToEmptyResult() throws {
        let json = "{\"suggestions\": []}"
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "text")
        #expect(suggestions.isEmpty)
    }

    // MARK: - Confidence filtering

    @Test func filtersSuggestionsWithConfidenceBelowSeven() throws {
        let json = """
        {
            "suggestions": [
                {"category": "rephrase", "revised_text": "Better", "explanation": "Good", "confidence": 6},
                {"category": "tone", "revised_text": "Nicer", "explanation": "OK", "confidence": 7},
                {"category": "rephrase", "revised_text": "Alt", "explanation": "Fine", "confidence": 5}
            ]
        }
        """
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "text")
        #expect(suggestions.count == 1)
        #expect(suggestions[0].category == .tone)
        #expect(suggestions[0].confidence == 7)
    }

    @Test func confidenceExactlySevenIsKept() throws {
        let json = """
        {"suggestions": [{"category": "tone", "revised_text": "R", "explanation": "E", "confidence": 7}]}
        """
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "text")
        #expect(suggestions.count == 1)
    }

    // MARK: - Malformed input

    @Test func malformedJSONThrows() {
        let data = Data("not json at all".utf8)
        #expect(throws: (any Error).self) {
            try LLMResponseDTO.toModels(from: data, originalText: "text")
        }
    }

    @Test func missingRequiredFieldsThrows() {
        // missing "explanation" field
        let json = "{\"suggestions\": [{\"category\": \"tone\", \"revised_text\": \"X\", \"confidence\": 8}]}"
        let data = Data(json.utf8)
        #expect(throws: (any Error).self) {
            try LLMResponseDTO.toModels(from: data, originalText: "text")
        }
    }

    // MARK: - Unknown / extra fields

    @Test func unknownCategoryIsDropped() throws {
        let json = """
        {
            "suggestions": [
                {"category": "unknown_future_category", "revised_text": "X", "explanation": "E", "confidence": 9},
                {"category": "tone", "revised_text": "Y", "explanation": "E2", "confidence": 8}
            ]
        }
        """
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "text")
        #expect(suggestions.count == 1)
        #expect(suggestions[0].category == .tone)
    }

    @Test func clarityCategoryDroppedPostDeletion_CLAR09() throws {
        // CLAR-09: LLM no longer prompted for clarity dimension. DTO silently drops
        // any stray "clarity" category via the unknown-rawValue guard in SuggestionDTO.toModel.
        let json = """
        {"suggestions": [{"category": "clarity", "revised_text": "X", "explanation": "E", "confidence": 9}]}
        """
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "text")
        #expect(suggestions.isEmpty)
    }

    @Test func extraUnknownFieldsAreIgnored() throws {
        let json = """
        {
            "suggestions": [
                {"category": "tone", "revised_text": "Better", "explanation": "Good", "confidence": 8, "future_field": "value", "another": 42}
            ]
        }
        """
        let data = Data(json.utf8)
        let suggestions = try LLMResponseDTO.toModels(from: data, originalText: "text")
        #expect(suggestions.count == 1)
        #expect(suggestions[0].category == .tone)
    }
}
