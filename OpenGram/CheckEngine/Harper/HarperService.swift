import Foundation

actor HarperService: GrammarCheckerProtocol {

    private var checker: HarperChecker
    private let dictionaryStore: any DictionaryStoreProtocol
    private let opinionatedProvider: @Sendable () -> Bool

    init(dictionaryStore: any DictionaryStoreProtocol,
         dialect: String,
         opinionatedProvider: @escaping @Sendable () -> Bool = {
             UserDefaults.standard.bool(forKey: ClarityKeys.clarityOpinionatedEnabledKey)
         }) {
        let words = dictionaryStore.loadWords()
        self.checker = HarperChecker(dialectAbbr: dialect, userWords: words)
        self.dictionaryStore = dictionaryStore
        self.opinionatedProvider = opinionatedProvider
    }

    func check(text: String) -> [Suggestion] {
        let raw = checker.check(text: text)
        let mapped = raw.compactMap { Suggestion(from: $0, in: text) }
        // One provider call per check() -- atomic snapshot for the whole filter
        // pass. The default provider reads UserDefaults; tests can inject a spy.
        let opinionated = opinionatedProvider()
        let severityFiltered = mapped.filter { !Self.shouldDropClarityLow($0, opinionatedEnabled: opinionated) }
        return Self.resolveExactRangeCategoryConflicts(severityFiltered)
    }

    func addToDictionary(word: String) {
        let updatedWords = checker.addToDictionary(word: word)
        dictionaryStore.saveWords(updatedWords)
    }

    func setRuleEnabled(key: String, enabled: Bool) {
        checker.setRuleEnabled(ruleKey: key, enabled: enabled)
    }

    /// Severity filter predicate (CLAR-08, CLAR-18). Nonisolated so unit tests
    /// can call it directly without actor hop. Guards on source AND category AND
    /// severity -- never drops non-clarity suggestions, never drops .high/.medium.
    nonisolated static func shouldDropClarityLow(
        _ s: Suggestion, opinionatedEnabled: Bool
    ) -> Bool {
        guard !opinionatedEnabled else { return false }
        return s.source == .harper && s.category == .clarity && s.severity == .low
    }

    /// Harper can emit a spelling fallback and a grammar/style correction for
    /// the exact same token. In the overlay that creates two competing
    /// underlines. Resolve those exact-range conflicts by keeping the correction
    /// closest to the original text; ties keep spelling. Larger grammar spans
    /// still keep inner spelling fixes.
    nonisolated static func resolveExactRangeCategoryConflicts(
        _ suggestions: [Suggestion]
    ) -> [Suggestion] {
        let nonSpelling = suggestions.filter { $0.category != .spelling }
        guard !nonSpelling.isEmpty else { return suggestions }

        var droppedIDs = Set<UUID>()
        for spelling in suggestions where spelling.category == .spelling {
            let competitors = nonSpelling.filter { $0.id != spelling.id && $0.range == spelling.range }
            guard !competitors.isEmpty else { continue }

            let spellingDistance = replacementDistance(from: spelling.original, to: spelling.primaryReplacement)
            let bestCompetitor = competitors.min {
                replacementDistance(from: $0.original, to: $0.primaryReplacement)
                    < replacementDistance(from: $1.original, to: $1.primaryReplacement)
            }
            let competitorDistance = bestCompetitor.map {
                replacementDistance(from: $0.original, to: $0.primaryReplacement)
            } ?? Int.max

            if competitorDistance < spellingDistance, let bestCompetitor {
                droppedIDs.insert(spelling.id)
                for competitor in competitors where competitor.id != bestCompetitor.id {
                    droppedIDs.insert(competitor.id)
                }
            } else {
                for competitor in competitors {
                    droppedIDs.insert(competitor.id)
                }
            }
        }

        return suggestions.filter { !droppedIDs.contains($0.id) }
    }

    private nonisolated static func replacementDistance(from original: String, to replacement: String?) -> Int {
        guard let replacement else { return Int.max }
        return damerauLevenshteinDistance(
            Array(original.lowercased()),
            Array(replacement.lowercased())
        )
    }

    private nonisolated static func damerauLevenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var rows = Array(
            repeating: Array(repeating: 0, count: rhs.count + 1),
            count: lhs.count + 1
        )
        for i in 0...lhs.count { rows[i][0] = i }
        for j in 0...rhs.count { rows[0][j] = j }

        for i in 1...lhs.count {
            for j in 1...rhs.count {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                rows[i][j] = min(
                    rows[i - 1][j] + 1,
                    rows[i][j - 1] + 1,
                    rows[i - 1][j - 1] + cost
                )
                if i > 1,
                   j > 1,
                   lhs[i - 1] == rhs[j - 2],
                   lhs[i - 2] == rhs[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }

        return rows[lhs.count][rhs.count]
    }
}
