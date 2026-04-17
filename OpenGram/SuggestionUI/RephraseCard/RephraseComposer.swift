import Foundation

/// Composes the full revised paragraph text by applying each LLMStyleSuggestion's
/// `revisedText` substitution to a copy of `paragraphText`. Uses descending start-offset
/// order so earlier offsets are not invalidated by later edits. D-21.
enum RephraseComposer {
    static func compose(paragraphText: String, issues: [LLMStyleSuggestion]) -> String {
        struct Edit { let range: Range<String.Index>; let replacement: String }
        var edits: [Edit] = []
        for issue in issues {
            guard let range = paragraphText.range(of: issue.originalText) else { continue }
            edits.append(Edit(range: range, replacement: issue.revisedText))
        }
        // Descending by lowerBound; ties broken by upperBound descending (longer match wins).
        // This ensures that for overlapping ranges at the same start, the widest match is applied
        // first and the narrower one is detected as an overlap and skipped.
        edits.sort {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound > $1.range.lowerBound
            }
            return $0.range.upperBound > $1.range.upperBound
        }
        var result = paragraphText
        // Track the earliest lowerBound already consumed by an applied edit.
        // Since we iterate descending, any subsequent edit whose upperBound exceeds
        // the applied lowerBound overlaps and is skipped.
        var appliedLower: String.Index? = nil
        for edit in edits {
            if let applied = appliedLower, edit.range.upperBound > applied { continue }
            guard edit.range.lowerBound < result.endIndex,
                  edit.range.upperBound <= result.endIndex else { continue }
            result.replaceSubrange(edit.range, with: edit.replacement)
            appliedLower = edit.range.lowerBound
        }
        return result
    }
}
