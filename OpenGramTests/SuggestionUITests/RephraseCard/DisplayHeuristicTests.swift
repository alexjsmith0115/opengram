import Testing
import Foundation
@testable import OpenGramLib

@Suite("DisplayHeuristic")
struct DisplayHeuristicTests {

    private func makeSuite() -> UserDefaults {
        let name = UUID().uuidString
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    private func makeConfig(minIssueCount: Int? = nil,
                            minWordCount: Int? = nil,
                            idleDebounceSeconds: Double? = nil) -> OpenGramConfig {
        let suite = makeSuite()
        if let minIssueCount { suite.set(minIssueCount, forKey: OpenGramConfig.minIssueCountKey) }
        if let minWordCount { suite.set(minWordCount, forKey: OpenGramConfig.minWordCountKey) }
        if let idleDebounceSeconds { suite.set(idleDebounceSeconds, forKey: OpenGramConfig.idleDebounceSecondsKey) }
        return OpenGramConfig(defaults: suite)
    }

    private func makeParagraph(_ text: String) -> Paragraph {
        Paragraph(text: text, range: text.startIndex..<text.endIndex, index: 0)
    }

    private func makeIssue(_ cat: LLMStyleSuggestion.Category) -> LLMStyleSuggestion {
        LLMStyleSuggestion(category: cat, originalText: "x", revisedText: "y", explanation: "", confidence: 8)
    }

    @Test func twoIssues_qualifies() {
        let h = DisplayHeuristic(config: makeConfig())
        let p = makeParagraph("short para")
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone), makeIssue(.tone)]) == true)
    }

    @Test func oneIssue_rephrase_qualifies() {
        let h = DisplayHeuristic(config: makeConfig())
        let p = makeParagraph("short")
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.rephrase)]) == true)
    }

    @Test func oneTone_longParagraph_qualifies() {
        let h = DisplayHeuristic(config: makeConfig())
        let p = makeParagraph("word " + String(repeating: "hello ", count: 12))  // >= 12 words
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == true)
    }

    @Test func oneTone_shortParagraph_doesNotQualify() {
        let h = DisplayHeuristic(config: makeConfig())
        let p = makeParagraph("only five words here indeed yes")  // 6 words, below 12
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == false)
    }

    @Test func emptyIssues_doesNotQualify() {
        let h = DisplayHeuristic(config: makeConfig())
        let p = makeParagraph("this paragraph has many words but no issues at all reported")
        #expect(h.qualifies(paragraph: p, issues: []) == false)
    }

    @Test func liveConfigRead_minIssueCount() {
        let suite = makeSuite()
        let cfg = OpenGramConfig(defaults: suite)
        let h = DisplayHeuristic(config: cfg)
        let p = makeParagraph("short")
        // 1 tone issue in short paragraph fails at default
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == false)
        // Lower threshold — next call re-reads UserDefaults, should qualify on count alone
        suite.set(1, forKey: OpenGramConfig.minIssueCountKey)
        #expect(h.qualifies(paragraph: p, issues: [makeIssue(.tone)]) == true)
    }
}
