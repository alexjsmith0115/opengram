import Foundation

/// Splits source text into paragraphs. Default implementation uses double-newline
/// boundaries; the protocol exists so future per-bundleID overrides (e.g. single-newline
/// for chat apps) can slot in without changing call sites. D-04, PRD FR-1.
protocol ParagraphSplitting: Sendable {
    func split(_ text: String) -> [Paragraph]
}

struct DoubleNewlineSplitter: ParagraphSplitting {

    func split(_ text: String) -> [Paragraph] {
        guard !text.isEmpty else { return [] }

        var paragraphs: [Paragraph] = []
        var emittedIndex = 0
        var segmentStart = text.startIndex
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "\n" {
                var runEnd = i
                while runEnd < text.endIndex, text[runEnd] == "\n" {
                    runEnd = text.index(after: runEnd)
                }
                let runLength = text.distance(from: i, to: runEnd)
                if runLength >= 2 {
                    emit(source: text,
                         from: segmentStart,
                         to: i,
                         index: &emittedIndex,
                         into: &paragraphs)
                    segmentStart = runEnd
                }
                i = runEnd
                continue
            }
            i = text.index(after: i)
        }

        if segmentStart < text.endIndex {
            emit(source: text,
                 from: segmentStart,
                 to: text.endIndex,
                 index: &emittedIndex,
                 into: &paragraphs)
        }

        return paragraphs
    }

    private func emit(source: String,
                      from start: String.Index,
                      to end: String.Index,
                      index: inout Int,
                      into out: inout [Paragraph]) {
        let range = start..<end
        let trimmed = source[range].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        out.append(Paragraph(text: trimmed, range: range, index: index))
        index += 1
    }
}
