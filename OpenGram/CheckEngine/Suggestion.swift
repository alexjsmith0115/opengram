import Foundation

// MARK: - Unicode Scalar Offset Conversion

extension String {

    /// Converts a Harper char index (Unicode scalar position) to a Swift String.Index.
    /// Harper's Span uses Rust `char` indices which are Unicode scalar values --
    /// a 1:1 match with Swift's `String.unicodeScalars` view.
    func indexFromCharOffset(_ offset: Int) -> String.Index? {
        guard offset >= 0 else { return nil }
        let scalars = self.unicodeScalars
        guard offset <= scalars.count else { return nil }
        return scalars.index(scalars.startIndex, offsetBy: offset)
    }

    /// Converts Harper Span start/end char indices to a Swift `Range<String.Index>`.
    /// Returns nil if either index is invalid or start > end.
    /// Snaps both bounds to grapheme cluster boundaries to prevent mid-cluster slicing
    /// (e.g., inside a ZWJ emoji sequence like family emoji).
    func rangeFromCharOffsets(start: Int, end: Int) -> Range<String.Index>? {
        guard let s = indexFromCharOffset(start),
              let e = indexFromCharOffset(end),
              s <= e else { return nil }
        let safeLower = self.rangeOfComposedCharacterSequence(at: s).lowerBound
        // endIndex is past all content; snapping only applies to indices within the string
        let safeUpper = (e == self.endIndex) ? e : self.rangeOfComposedCharacterSequence(at: e).lowerBound
        guard safeLower <= safeUpper else { return nil }
        return safeLower..<safeUpper
    }
}

// MARK: - Suggestion Category (Swift-side, distinct from UniFFI-generated SuggestionCategory)

enum CheckCategory: Sendable, Equatable, Hashable {
    /// Harper LintKind.Spelling -- rendered red (D-03)
    case spelling
    /// All other LintKind variants -- rendered blue (D-03)
    case grammarPunctuation
    /// LLM: hedging, passive voice, weak phrasing -- rendered purple
    case tone
    /// LLM: wordiness, redundancy, complex structure -- rendered orange
    case clarity
    /// LLM: structural rewrites for better flow -- rendered teal
    case rephrase
}

// MARK: - Suggestion Source

enum SuggestionSource: Sendable {
    case harper
    case llm
}

// MARK: - Suggestion Model

struct Suggestion: Identifiable, Sendable {
    let id: UUID
    let range: Range<String.Index>
    let original: String
    let primaryReplacement: String?
    let allReplacements: [String]
    let message: String
    let category: CheckCategory
    let source: SuggestionSource
    let priority: UInt8
    /// D-23: non-nil for LLM-sourced suggestions carrying the paragraph's
    /// `ParagraphHash` for Dismiss-path and card-dedup (WR-02).
    /// Nil for Harper suggestions and flag-off LLM suggestions.
    let paragraphHash: ParagraphHash?
}

extension Suggestion {
    /// Creates a Suggestion from a UniFFI-generated GrammarSuggestion.
    /// Returns nil if the char offsets cannot be converted to a valid Swift string range.
    init?(from raw: GrammarSuggestion, in text: String) {
        guard let range = text.rangeFromCharOffsets(
            start: Int(raw.startChar),
            end: Int(raw.endChar)
        ) else { return nil }

        let category: CheckCategory
        switch raw.category {
        case .spelling:
            category = .spelling
        case .grammarPunctuation:
            category = .grammarPunctuation
        }

        self.init(
            id: UUID(),
            range: range,
            original: String(text[range]),
            primaryReplacement: raw.primaryReplacement,
            allReplacements: raw.allReplacements,
            message: raw.message,
            category: category,
            source: .harper,
            priority: raw.priority,
            paragraphHash: nil
        )
    }
}
