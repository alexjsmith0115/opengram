import Testing
@testable import OpenGramLib

@Suite("RephraseComposer")
struct RephraseComposerTests {

    private func issue(_ orig: String, _ revised: String) -> LLMStyleSuggestion {
        LLMStyleSuggestion(category: .tone, originalText: orig, revisedText: revised, explanation: "", confidence: 8)
    }

    @Test func noIssues_returnsOriginal() {
        #expect(RephraseComposer.compose(paragraphText: "hello world", issues: []) == "hello world")
    }

    @Test func singleReplacement_applies() {
        let out = RephraseComposer.compose(
            paragraphText: "the quick brown fox",
            issues: [issue("quick", "slow")]
        )
        #expect(out == "the slow brown fox")
    }

    @Test func twoNonOverlappingReplacements_applyInDescendingOrder() {
        let out = RephraseComposer.compose(
            paragraphText: "hello world and goodbye",
            issues: [issue("hello", "hi"), issue("goodbye", "bye")]
        )
        #expect(out == "hi world and bye")
    }

    @Test func unfindableOriginal_skipped() {
        let out = RephraseComposer.compose(
            paragraphText: "a b c",
            issues: [issue("xyz", "qqq"), issue("b", "B")]
        )
        #expect(out == "a B c")
    }

    @Test func overlappingRanges_laterWinsByDescendingIteration() {
        // Both issues match "hello world"; descending iteration applies the rightmost-starting match first.
        // If both start at same location, `range(of:)` returns the FIRST match; descending order still deterministic.
        let out = RephraseComposer.compose(
            paragraphText: "hello world",
            issues: [issue("hello world", "GREETING"), issue("hello", "HI")]
        )
        // First sort: the full-string match has lowerBound 0; the "hello" match also has lowerBound 0.
        // Tie — sort is stable in Swift; iteration order applies both. The first applied replaces
        // "hello world" with "GREETING"; the second then tries to find "hello" in "GREETING" which fails.
        #expect(out == "GREETING")
    }
}
