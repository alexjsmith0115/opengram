import Testing
import Foundation
@testable import OpenGramLib

@Suite struct ParagraphSplitterTests {

    private let splitter = DoubleNewlineSplitter()

    @Test func emptyStringReturnsNoParagraphs() {
        #expect(splitter.split("") == [])
    }

    @Test func whitespaceOnlyStringReturnsNoParagraphs() {
        #expect(splitter.split("   \n  \t  ") == [])
    }

    @Test func singleParagraphReturnsOneParagraph() {
        let source = "hello world"
        let result = splitter.split(source)
        #expect(result.count == 1)
        #expect(result[0].text == "hello world")
        #expect(result[0].index == 0)
        #expect(String(source[result[0].range]) == "hello world")
    }

    @Test func doubleNewlineSplitsIntoTwoParagraphs() {
        let result = splitter.split("alpha\n\nbeta")
        #expect(result.count == 2)
        #expect(result.map(\.text) == ["alpha", "beta"])
        #expect(result.map(\.index) == [0, 1])
    }

    @Test func multipleBlankLinesCollapseToOneBoundary() {
        let result = splitter.split("a\n\n\n\nb")
        #expect(result.count == 2)
        #expect(result.map(\.text) == ["a", "b"])
    }

    @Test func whitespaceOnlySegmentIsDropped() {
        let result = splitter.split("a\n\n   \n\nb")
        #expect(result.count == 2)
        #expect(result.map(\.text) == ["a", "b"])
    }

    @Test func paragraphTextIsTrimmed() {
        let result = splitter.split("  foo  \n\nbar")
        #expect(result[0].text == "foo")
    }

    @Test func paragraphRangeCoversUntrimmedSpan() {
        let source = "  foo  \n\nbar"
        let result = splitter.split(source)
        #expect(String(source[result[0].range]) == "  foo  ")
    }

    @Test func indicesAreSequentialFromZero() {
        let result = splitter.split("a\n\nb\n\nc")
        #expect(result.map(\.index) == [0, 1, 2])
    }

    @Test func singleNewlineStaysWithinParagraph() {
        let result = splitter.split("line1\nline2\n\npara2")
        #expect(result.count == 2)
        #expect(result[0].text == "line1\nline2")
    }

    @Test func emojiAndCJKSurviveRoundtrip() {
        let result = splitter.split("日本語\n\n🎉 party")
        #expect(result.count == 2)
        #expect(result[0].text == "日本語")
        #expect(result[1].text == "🎉 party")
    }

    @Test func performance500ParagraphsUnder10ms() {
        let oneParagraph = String(repeating: "abc ", count: 20)
        let corpus = Array(repeating: oneParagraph, count: 500).joined(separator: "\n\n")
        _ = splitter.split(corpus) // warm-up
        let start = Date()
        let result = splitter.split(corpus)
        let elapsed = Date().timeIntervalSince(start)
        #expect(result.count == 500)
        #expect(elapsed < 0.010)
    }
}
