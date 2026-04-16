import Testing
import Foundation
@testable import OpenGramLib

@Suite struct ParagraphHasherTests {

    private let hasher = Sha256ParagraphHasher()

    @Test func identicalStringsHashIdentically() {
        #expect(hasher.hash("hello world") == hasher.hash("hello world"))
    }

    @Test func leadingTrailingWhitespaceIsNormalized() {
        #expect(hasher.hash("  hello  ") == hasher.hash("hello"))
    }

    @Test func internalWhitespaceRunsCollapse() {
        #expect(hasher.hash("foo   bar") == hasher.hash("foo bar"))
    }

    @Test func mixedWhitespaceTypesCollapse() {
        #expect(hasher.hash("foo  bar\tbaz") == hasher.hash("foo bar baz"))
    }

    @Test func internalNewlinesCollapseToSpace() {
        #expect(hasher.hash("foo\nbar") == hasher.hash("foo bar"))
    }

    @Test func caseChangeAltersHash() {
        #expect(hasher.hash("Foo bar") != hasher.hash("foo bar"))
    }

    @Test func punctuationChangeAltersHash() {
        #expect(hasher.hash("foo bar.") != hasher.hash("foo bar"))
    }

    @Test func nfcNormalizationMakesComposedAndDecomposedEqual() {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        #expect(hasher.hash(composed) == hasher.hash(decomposed))
    }

    @Test func emptyAndWhitespaceOnlyHashIdentically() {
        #expect(hasher.hash("") == hasher.hash("   \t\n "))
    }

    @Test func performance500ParagraphsUnder10ms() {
        let inputs = (0..<500).map { "paragraph \($0) body with some filler text" }
        _ = inputs.map { hasher.hash($0) }
        let start = Date()
        let results = inputs.map { hasher.hash($0) }
        let elapsed = Date().timeIntervalSince(start)
        #expect(results.count == 500)
        #expect(elapsed < 0.010)
    }
}
