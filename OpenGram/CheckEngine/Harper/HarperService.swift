import Foundation

actor HarperService: GrammarCheckerProtocol {

    private var checker: HarperChecker
    private let dictionaryStore: any DictionaryStoreProtocol
    private let defaults: UserDefaults

    init(dictionaryStore: any DictionaryStoreProtocol,
         dialect: String,
         defaults: UserDefaults = .standard) {
        let words = dictionaryStore.loadWords()
        self.checker = HarperChecker(dialectAbbr: dialect, userWords: words)
        self.dictionaryStore = dictionaryStore
        self.defaults = defaults
    }

    func check(text: String) -> [Suggestion] {
        let raw = checker.check(text: text)
        let mapped = raw.compactMap { Suggestion(from: $0, in: text) }
        // One UserDefaults read per check() call -- atomic snapshot for the whole
        // filter pass. Avoids a per-suggestion read if the closure inlined it.
        let opinionated = defaults.bool(forKey: ClarityKeys.clarityOpinionatedEnabledKey)
        return mapped.filter { !Self.shouldDropClarityLow($0, opinionatedEnabled: opinionated) }
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
}
