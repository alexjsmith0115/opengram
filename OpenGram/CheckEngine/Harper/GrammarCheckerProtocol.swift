/// DI contract for grammar checking. All methods are async because the concrete
/// implementation (HarperService) is a Swift actor.
/// Named GrammarCheckerProtocol to avoid collision with the UniFFI-generated
/// HarperCheckerProtocol in HarperBridge.swift.
protocol GrammarCheckerProtocol: Sendable {
    func check(text: String) async -> [Suggestion]
    func addToDictionary(word: String) async
    func setRuleEnabled(key: String, enabled: Bool) async
}
