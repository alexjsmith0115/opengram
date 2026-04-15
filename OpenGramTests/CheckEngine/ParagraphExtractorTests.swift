import Testing
@preconcurrency import ApplicationServices
@testable import OpenGramLib

@Suite struct ParagraphExtractorTests {

    private let dummyElement = AXUIElementCreateSystemWide()

    // MARK: - Priority 1: selection

    @Test func returnsSelectedTextWhenSelectionIsNonEmpty() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        // Select "Second paragraph."
        let selectionStart = (text as NSString).range(of: "Second paragraph.").location
        let context = TextContext(
            text: text,
            bundleID: "com.test",
            extractionMethod: .axDirectSelection,
            selectionRange: CFRange(location: selectionStart, length: 17),
            elementBounds: nil,
            axElement: dummyElement
        )
        #expect(ParagraphExtractor.extract(from: context) == "Second paragraph.")
    }

    // MARK: - Priority 2: paragraph around cursor

    @Test func extractsParagraphAroundCursorInMiddleOfMultiParagraphText() {
        let text = "First line.\nSecond line.\nThird line."
        // Cursor at offset 14 — inside "Second line."
        let context = TextContext(
            text: text,
            bundleID: "com.test",
            extractionMethod: .axDirectFull,
            selectionRange: CFRange(location: 14, length: 0),
            elementBounds: nil,
            axElement: dummyElement
        )
        #expect(ParagraphExtractor.extract(from: context) == "Second line.")
    }

    @Test func extractsParagraphWhenCursorIsAtStartOfText() {
        let text = "First paragraph.\nSecond paragraph."
        let context = TextContext(
            text: text,
            bundleID: "com.test",
            extractionMethod: .axDirectFull,
            selectionRange: CFRange(location: 0, length: 0),
            elementBounds: nil,
            axElement: dummyElement
        )
        #expect(ParagraphExtractor.extract(from: context) == "First paragraph.")
    }

    @Test func extractsParagraphWhenCursorIsAtEndOfText() {
        let text = "First paragraph.\nSecond paragraph."
        let cursorOffset = text.unicodeScalars.count
        let context = TextContext(
            text: text,
            bundleID: "com.test",
            extractionMethod: .axDirectFull,
            selectionRange: CFRange(location: cursorOffset, length: 0),
            elementBounds: nil,
            axElement: dummyElement
        )
        #expect(ParagraphExtractor.extract(from: context) == "Second paragraph.")
    }

    @Test func returnsSingleParagraphTextWithNoNewlines() {
        let text = "Just one paragraph with no newlines anywhere."
        let context = TextContext(
            text: text,
            bundleID: "com.test",
            extractionMethod: .axDirectFull,
            selectionRange: CFRange(location: 5, length: 0),
            elementBounds: nil,
            axElement: dummyElement
        )
        #expect(ParagraphExtractor.extract(from: context) == text)
    }

    // MARK: - Priority 3: fallback

    @Test func capsResultAt2000CharactersForFallback() {
        let text = String(repeating: "a", count: 3000)
        // No selection range → fallback
        let context = TextContext(
            text: text,
            bundleID: "com.test",
            extractionMethod: .axDirectFull,
            selectionRange: nil,
            elementBounds: nil,
            axElement: dummyElement
        )
        let result = ParagraphExtractor.extract(from: context)
        #expect(result.count == 2000)
    }

    @Test func returnsEmptyStringForEmptyText() {
        let context = TextContext(
            text: "",
            bundleID: "com.test",
            extractionMethod: .axDirectFull,
            selectionRange: nil,
            elementBounds: nil,
            axElement: dummyElement
        )
        #expect(ParagraphExtractor.extract(from: context) == "")
    }
}
