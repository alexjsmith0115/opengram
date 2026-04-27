import Foundation

/// Single source of truth for converting AX-supplied UTF-16 CFRanges into Swift
/// `String.Index` ranges. Used by both the freshness-check read path and the
/// writeback splice path so they cannot disagree on multi-byte text.
enum AXRangeIndex {
    static func substring(of text: String, at cfRange: CFRange) -> String? {
        guard let r = indexRange(in: text, cfRange: cfRange) else { return nil }
        return String(text[r])
    }

    static func replacing(in text: String, at cfRange: CFRange, with replacement: String) -> String? {
        guard let r = indexRange(in: text, cfRange: cfRange) else { return nil }
        return text.replacingCharacters(in: r, with: replacement)
    }

    static func indexRange(in text: String, cfRange: CFRange) -> Range<String.Index>? {
        guard cfRange.location >= 0, cfRange.length >= 0 else { return nil }
        let utf16 = text.utf16
        guard cfRange.location + cfRange.length <= utf16.count else { return nil }

        guard let lower16 = utf16.index(utf16.startIndex,
                                       offsetBy: cfRange.location,
                                       limitedBy: utf16.endIndex),
              let upper16 = utf16.index(lower16,
                                       offsetBy: cfRange.length,
                                       limitedBy: utf16.endIndex),
              let lower = String.Index(lower16, within: text),
              let upper = String.Index(upper16, within: text)
        else { return nil }
        return lower..<upper
    }
}
