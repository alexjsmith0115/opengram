actor HarperService: GrammarCheckerProtocol {

    private var checker: HarperChecker
    private let dictionaryStore: any DictionaryStoreProtocol

    init(dictionaryStore: any DictionaryStoreProtocol, dialect: String) {
        let words = dictionaryStore.loadWords()
        self.checker = HarperChecker(dialectAbbr: dialect, userWords: words)
        self.dictionaryStore = dictionaryStore
    }

    func check(text: String) -> [Suggestion] {
        let raw = checker.check(text: text)
        return raw.compactMap { Suggestion(from: $0, in: text) }
    }

    func addToDictionary(word: String) {
        let updatedWords = checker.addToDictionary(word: word)
        dictionaryStore.saveWords(updatedWords)
    }

    func setRuleEnabled(key: String, enabled: Bool) {
        checker.setRuleEnabled(ruleKey: key, enabled: enabled)
    }
}
