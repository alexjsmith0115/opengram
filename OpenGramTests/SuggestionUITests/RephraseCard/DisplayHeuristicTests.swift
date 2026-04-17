import Testing
import Foundation
@testable import OpenGramLib

@Suite("DisplayHeuristic")
struct DisplayHeuristicTests {

    private struct FakeConfig: IncrementalConfig {
        var isIncrementalCheckingEnabled: Bool = true
        var paragraphRephraseCardEnabled: Bool = false
        var minIssueCount: Int = 2
        var minWordCount: Int = 12
        var idleDebounceSeconds: TimeInterval = 1.5
    }

    private func makeParagraph(_ text: String) -> Paragraph {
        Paragraph(text: text, range: text.startIndex..<text.endIndex, index: 0)
    }

    private func makeIssue(_ cat: LLMStyleSuggestion.Category) -> LLMStyleSuggestion {
        LLMStyleSuggestion(category: cat, originalText: "x", revisedText: "y", explanation: "", confidence: 8)
    }

    @Test func twoIssues_qualifies() {
        let h = DisplayHeuristic(config: FakeConfig())
        let p = makeParagraph("short para")
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone), makeIssue(.tone)]) == true)
    }

    @Test func oneIssue_clarity_qualifies() {
        let h = DisplayHeuristic(config: FakeConfig())
        let p = makeParagraph("short")
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.clarity)]) == true)
    }

    @Test func oneIssue_rephrase_qualifies() {
        let h = DisplayHeuristic(config: FakeConfig())
        let p = makeParagraph("short")
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.rephrase)]) == true)
    }

    @Test func oneTone_longParagraph_qualifies() {
        let h = DisplayHeuristic(config: FakeConfig())
        let p = makeParagraph("word " + String(repeating: "hello ", count: 12))  // >= 12 words
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == true)
    }

    @Test func oneTone_shortParagraph_doesNotQualify() {
        let h = DisplayHeuristic(config: FakeConfig())
        let p = makeParagraph("only five words here indeed yes")  // 6 words, below 12
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == false)
    }

    @Test func emptyIssues_doesNotQualify() {
        let h = DisplayHeuristic(config: FakeConfig())
        let p = makeParagraph("this paragraph has many words but no issues at all reported")
        #expect(h.qualifies(paragraph: p, issues: []) == false)
    }

    @Test func liveConfigRead_minIssueCount() {
        final class Mutable: IncrementalConfig, @unchecked Sendable {
            var isIncrementalCheckingEnabled: Bool = true
            var paragraphRephraseCardEnabled: Bool = false
            var minIssueCount: Int = 2
            var minWordCount: Int = 12
            var idleDebounceSeconds: TimeInterval = 1.5
        }
        let cfg = Mutable()
        let h = DisplayHeuristic(config: cfg)
        let p = makeParagraph("short")
        // 1 tone issue in short paragraph fails at default
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == false)
        // Lower threshold — now it should qualify on count alone
        cfg.minIssueCount = 1
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == true)
    }
}
