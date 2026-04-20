import Foundation

/// Pure-value ViewModel consumed by the SwiftUI `RephraseCardView`.
/// Carries the full revised paragraph, the diff segments, and Accept/Dismiss callbacks.
/// The toggle state (`showFullDiff`) is owned by the View as `@State` per D-03.
struct RephraseCardViewModel {
    let paragraph: Paragraph
    let issues: [LLMStyleSuggestion]
    /// Full composed revised paragraph (via `RephraseComposer.compose`). D-21.
    let rephrase: String
    /// Precomputed diff segments between `paragraph.text` and `rephrase`.
    let segments: [DiffSegment]
    /// Header text computed from the merged Harper+LLM category set (D-22).
    let header: String
    let onAccept: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void

    /// FR-16 / D-18 / D-22: header reflects the merged set of issue categories.
    /// Spelling folds silently; empty set returns "" (card must not appear).
    static func headerText(for categories: Set<CheckCategory>) -> String {
        let hasClarity = categories.contains(.clarity) || categories.contains(.rephrase)
        let hasGrammar = categories.contains(.grammarPunctuation)
        switch (hasClarity, hasGrammar) {
        case (true, true):   return "Improve clarity and fix grammar"
        case (true, false):  return "Improve clarity"
        case (false, true):  return "Fix grammar"
        case (false, false): return ""
        }
    }

    /// Category-mapping helper: LLMStyleSuggestion.Category → CheckCategory.
    /// `.tone` collapses to `.clarity` (tone adjustments are a clarity concern for
    /// header purposes — header never surfaces "tone" as its own label).
    /// `.rephrase` maps through unchanged.
    static func checkCategory(from llmCategory: LLMStyleSuggestion.Category) -> CheckCategory {
        switch llmCategory {
        case .tone: return .clarity
        case .rephrase: return .rephrase
        }
    }
}
