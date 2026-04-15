import Foundation

/// Scopes text from a `TextContext` to the most relevant unit for LLM style checking.
///
/// Priority order:
/// 1. User's selection (if non-empty)
/// 2. Paragraph around the cursor (newline-bounded)
/// 3. First 2000 characters of the full text
enum ParagraphExtractor {

    static func extract(from context: TextContext) -> String {
        let text = context.text

        // Priority 1: non-empty user selection
        if let selection = selectedText(from: context), !selection.isEmpty {
            return selection
        }

        // Priority 2: paragraph around cursor
        if let range = context.selectionRange, let paragraph = paragraph(in: text, around: range) {
            return paragraph
        }

        // Priority 3: fallback — first 2000 characters
        return String(text.prefix(2000))
    }

    // MARK: - Private

    private static func selectedText(from context: TextContext) -> String? {
        guard let cfRange = context.selectionRange,
              cfRange.length > 0 else { return nil }
        return substring(of: context.text, cfRange: cfRange)
    }

    private static func paragraph(in text: String, around cfRange: CFRange) -> String? {
        // Use the cursor position (start of selection) to find the enclosing paragraph.
        let scalars = text.unicodeScalars
        let totalScalars = scalars.count
        let cursorOffset = max(0, min(cfRange.location, totalScalars))

        let cursorIndex = scalars.index(scalars.startIndex, offsetBy: cursorOffset)
        // Snap to the nearest String.Index so we can search for newlines
        let textIndex = String.Index(cursorIndex, within: text) ?? text.startIndex

        // Scan backward for preceding newline (or start of string)
        let paragraphStart: String.Index
        if let newlineBefore = text[..<textIndex].lastIndex(of: "\n") {
            paragraphStart = text.index(after: newlineBefore)
        } else {
            paragraphStart = text.startIndex
        }

        // Scan forward for following newline (or end of string)
        let paragraphEnd: String.Index
        if let newlineAfter = text[textIndex...].firstIndex(of: "\n") {
            paragraphEnd = newlineAfter
        } else {
            paragraphEnd = text.endIndex
        }

        guard paragraphStart <= paragraphEnd else { return nil }
        return String(text[paragraphStart..<paragraphEnd])
    }

    private static func substring(of text: String, cfRange: CFRange) -> String? {
        let scalars = text.unicodeScalars
        let count = scalars.count
        let start = cfRange.location
        let end = start + cfRange.length
        guard start >= 0, end <= count, start <= end else { return nil }
        let startIdx = scalars.index(scalars.startIndex, offsetBy: start)
        let endIdx = scalars.index(scalars.startIndex, offsetBy: end)
        guard let swiftStart = String.Index(startIdx, within: text),
              let swiftEnd = String.Index(endIdx, within: text) else { return nil }
        return String(text[swiftStart..<swiftEnd])
    }
}
