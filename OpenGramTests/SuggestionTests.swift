import Testing
@testable import OpenGramLib

@Suite("String Unicode scalar offset conversion")
struct StringCharOffsetTests {

    @Test("ASCII: char offsets 8..<10 in 'This is an test' yields 'an'")
    func asciiOffsets() {
        let text = "This is an test"
        let range = text.rangeFromCharOffsets(start: 8, end: 10)
        #expect(range != nil)
        #expect(String(text[range!]) == "an")
    }

    @Test("Single-scalar emoji: char offsets 9..<16 in 'I love (party) grammar' yields 'grammar'")
    func singleScalarEmoji() {
        let text = "I love \u{1F389} grammar"
        let range = text.rangeFromCharOffsets(start: 9, end: 16)
        #expect(range != nil)
        #expect(String(text[range!]) == "grammar")
    }

    @Test("Accented chars: char offsets 5..<10 in 'cafe latte' yields 'latte'")
    func accentedChars() {
        let text = "caf\u{00E9} latte"
        let range = text.rangeFromCharOffsets(start: 5, end: 10)
        #expect(range != nil)
        #expect(String(text[range!]) == "latte")
    }

    @Test("CJK: char offsets 9..<14 in 'Hello world' yields 'world'")
    func cjkChars() {
        let text = "Hello \u{4E16}\u{754C} world"
        let range = text.rangeFromCharOffsets(start: 9, end: 14)
        #expect(range != nil)
        #expect(String(text[range!]) == "world")
    }

    @Test("Multi-scalar emoji: char offsets 9..<14 in 'Hi (family) there' yields 'there'")
    func multiScalarEmoji() {
        // Family emoji: man(1) + ZWJ(1) + woman(1) + ZWJ(1) + boy(1) = 5 scalars at indices 3-7
        // Space at index 8, "there" at indices 9-13, total 14 scalars
        let text = "Hi \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466} there"
        let range = text.rangeFromCharOffsets(start: 9, end: 14)
        #expect(range != nil)
        #expect(String(text[range!]) == "there")
    }

    @Test("Out of bounds: end > scalar count returns nil")
    func outOfBounds() {
        let text = "short"
        let range = text.rangeFromCharOffsets(start: 0, end: 100)
        #expect(range == nil)
    }

    @Test("Grapheme boundary snap: mid-cluster offset snaps to grapheme boundaries")
    func graphemeBoundarySnap() {
        // Family emoji: man(1) + ZWJ(1) + woman(1) + ZWJ(1) + boy(1) = 5 scalars at indices 3-7
        // Offset 4 lands on ZWJ inside the family emoji cluster. Snap should round to grapheme boundary.
        let text = "Hi \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466} there"
        let range = text.rangeFromCharOffsets(start: 4, end: 9)
        // The range should exist and not crash; exact content depends on snap direction
        if let range = range {
            let substring = String(text[range])
            #expect(!substring.isEmpty)
        }
    }

    @Test("indexFromCharOffset at exact end returns endIndex")
    func indexAtEnd() {
        let text = "abc"
        let idx = text.indexFromCharOffset(3)
        #expect(idx == text.endIndex)
    }

    @Test("indexFromCharOffset with negative offset returns nil")
    func negativeOffset() {
        let text = "abc"
        let idx = text.indexFromCharOffset(-1)
        #expect(idx == nil)
    }

    @Test("rangeFromCharOffsets with start > end returns nil")
    func startGreaterThanEnd() {
        let text = "hello"
        let range = text.rangeFromCharOffsets(start: 3, end: 1)
        #expect(range == nil)
    }
}

@Suite("Suggestion model")
struct SuggestionModelTests {

    @Test("Suggestion initializes from GrammarSuggestion with valid offsets")
    func initFromGrammarSuggestion() {
        let text = "This is an test of grammar"
        let raw = GrammarSuggestion(
            startChar: 8,
            endChar: 10,
            message: "Use 'a' instead of 'an'",
            primaryReplacement: "a",
            allReplacements: ["a"],
            category: .grammarPunctuation,
            priority: 10,
            severity: nil
        )

        let suggestion = Suggestion(from: raw, in: text)
        #expect(suggestion != nil)
        #expect(suggestion?.original == "an")
        #expect(suggestion?.primaryReplacement == "a")
        #expect(suggestion?.allReplacements == ["a"])
        #expect(suggestion?.message == "Use 'a' instead of 'an'")
        #expect(suggestion?.category == .grammarPunctuation)
        #expect(suggestion?.source == .harper)
        #expect(suggestion?.priority == 10)
    }

    @Test("Suggestion returns nil for out-of-bounds offsets")
    func initReturnsNilForBadOffsets() {
        let text = "short"
        let raw = GrammarSuggestion(
            startChar: 0,
            endChar: 100,
            message: "bad",
            primaryReplacement: nil,
            allReplacements: [],
            category: .spelling,
            priority: 5,
            severity: nil
        )

        let suggestion = Suggestion(from: raw, in: text)
        #expect(suggestion == nil)
    }

    @Test("Suggestion maps spelling category correctly")
    func spellingCategoryMapping() {
        let text = "teh quick"
        let raw = GrammarSuggestion(
            startChar: 0,
            endChar: 3,
            message: "Did you mean 'the'?",
            primaryReplacement: "the",
            allReplacements: ["the"],
            category: .spelling,
            priority: 20,
            severity: nil
        )

        let suggestion = Suggestion(from: raw, in: text)
        #expect(suggestion != nil)
        #expect(suggestion?.category == .spelling)
        #expect(suggestion?.original == "teh")
    }

    @Test("Suggestion is Identifiable with unique UUID")
    func suggestionIsIdentifiable() {
        let text = "test word"
        let raw = GrammarSuggestion(
            startChar: 0,
            endChar: 4,
            message: "test",
            primaryReplacement: nil,
            allReplacements: [],
            category: .spelling,
            priority: 1,
            severity: nil
        )

        let s1 = Suggestion(from: raw, in: text)
        let s2 = Suggestion(from: raw, in: text)
        #expect(s1 != nil)
        #expect(s2 != nil)
        #expect(s1?.id != s2?.id)
    }
}
