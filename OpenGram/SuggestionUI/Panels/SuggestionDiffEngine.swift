import Foundation

/// Identifies a suggestion by its content and position, not by UUID.
///
/// Harper regenerates UUIDs on every check pass, so UUID-based comparison
/// would mark every suggestion as changed even when nothing moved.
struct SuggestionKey: Hashable {
    let scalarStart: Int
    let scalarLength: Int
    let original: String
    let category: CheckCategory
}

/// Result of diffing two suggestion arrays.
struct SuggestionDiffResult {
    /// Pairs of (oldIndex, newIndex) for suggestions present in both old and new.
    let unchanged: [(oldIndex: Int, newIndex: Int)]
    /// Indices into the new array for suggestions that did not exist in old.
    let added: [Int]
    /// Indices into the old array for suggestions that are no longer in new.
    let removed: [Int]
}

/// Computes the diff between two suggestion sets for flicker-free overlay updates.
///
/// Matching is by scalar offset + original text + category, not UUID (D-12).
enum SuggestionDiffEngine {

    static func diff(
        old: [Suggestion],
        oldOffsets: [(scalarStart: Int, scalarLength: Int)],
        new: [Suggestion],
        newOffsets: [(scalarStart: Int, scalarLength: Int)]
    ) -> SuggestionDiffResult {
        var oldKeyToIndex: [SuggestionKey: Int] = Dictionary(minimumCapacity: old.count)
        for (i, suggestion) in old.enumerated() {
            oldKeyToIndex[key(for: suggestion, offset: oldOffsets[i])] = i
        }

        var unchanged: [(oldIndex: Int, newIndex: Int)] = []
        var added: [Int] = []

        for (j, suggestion) in new.enumerated() {
            let k = key(for: suggestion, offset: newOffsets[j])
            if let oldIndex = oldKeyToIndex[k] {
                unchanged.append((oldIndex: oldIndex, newIndex: j))
                oldKeyToIndex.removeValue(forKey: k)
            } else {
                added.append(j)
            }
        }

        let removed = Array(oldKeyToIndex.values)
        return SuggestionDiffResult(unchanged: unchanged, added: added, removed: removed)
    }

    static func key(
        for suggestion: Suggestion,
        offset: (scalarStart: Int, scalarLength: Int)
    ) -> SuggestionKey {
        SuggestionKey(
            scalarStart: offset.scalarStart,
            scalarLength: offset.scalarLength,
            original: suggestion.original,
            category: suggestion.category
        )
    }
}
