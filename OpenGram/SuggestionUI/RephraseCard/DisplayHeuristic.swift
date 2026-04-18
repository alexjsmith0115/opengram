import Foundation

/// FR-12 / REPH-02 qualifier. Reads `OpenGramConfig` on every call so Advanced Settings
/// changes take effect on the next check cycle without relaunch (D-11, D-03 live-read pattern).
struct DisplayHeuristic: Sendable {
    let config: OpenGramConfig

    func qualifies(paragraph: Paragraph, issues: [LLMStyleSuggestion]) -> Bool {
        if issues.count >= config.minIssueCount { return true }
        if issues.contains(where: { $0.category == .clarity || $0.category == .rephrase }) { return true }
        let wordCount = paragraph.text.split(whereSeparator: { $0.isWhitespace }).count
        if wordCount >= config.minWordCount, !issues.isEmpty { return true }
        return false
    }
}
