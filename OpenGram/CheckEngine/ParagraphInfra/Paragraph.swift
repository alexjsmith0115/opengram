import Foundation

/// Paragraph emitted by `ParagraphSplitting`. `text` is trimmed; `range` covers the
/// untrimmed source span so downstream code can reposition without re-splitting. D-01, D-03.
struct Paragraph: Sendable, Equatable {
    let text: String
    let range: Range<String.Index>
    let index: Int
}
