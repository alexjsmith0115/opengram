import Testing
import Foundation
@testable import OpenGramLib

@Suite("HarperService Integration Tests")
struct HarperServiceTests {

    private func makeService(dialect: String = "US") -> HarperService {
        let store = DictionaryStore(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        return HarperService(dictionaryStore: store, dialect: dialect)
    }

    // MARK: - GRAM-01: Spelling detection

    @Test("detects spelling errors with category .spelling")
    func spellingDetection() async {
        let service = makeService()
        let suggestions = await service.check(text: "I love this prodcut very much.")
        let spellingErrors = suggestions.filter { $0.category == .spelling }
        #expect(!spellingErrors.isEmpty, "Expected at least one spelling suggestion for 'prodcut'")
        let prodcutError = spellingErrors.first { $0.original.lowercased().contains("prodcut") }
        #expect(prodcutError != nil, "Expected a spelling error specifically for 'prodcut'")
    }

    // MARK: - GRAM-02: Grammar detection

    @Test("detects grammar errors with category .grammarPunctuation")
    func grammarDetection() async {
        let service = makeService()
        let suggestions = await service.check(text: "This is an test of the system.")
        let grammarErrors = suggestions.filter { $0.category == .grammarPunctuation }
        #expect(!grammarErrors.isEmpty, "Expected at least one grammar suggestion for 'an test'")
    }

    // MARK: - GRAM-03: Punctuation detection

    @Test("detects punctuation errors like missing apostrophe")
    func punctuationDetection() async {
        let service = makeService()
        let suggestions = await service.check(text: "Dont forget the milk.")
        #expect(!suggestions.isEmpty, "Expected at least one suggestion for missing apostrophe in 'Dont'")
        let apostropheError = suggestions.first { $0.original.lowercased().contains("dont") }
        #expect(apostropheError != nil, "Expected a suggestion specifically for 'Dont'")
    }

    // MARK: - GRAM-04: Performance under 50ms

    @Test("checks 500-word text in under 50ms")
    func performanceUnder50ms() async {
        let service = makeService()
        let sentence = "The quick brown fox jumps over the lazy dog near the river bank. "
        let repetitions = 500 / sentence.split(separator: " ").count
        let longText = String(repeating: sentence, count: max(repetitions, 40))

        let clock = ContinuousClock()
        let duration = await clock.measure {
            _ = await service.check(text: longText)
        }
        #expect(duration < .milliseconds(50), "Harper check took \(duration), expected under 50ms")
    }

    // MARK: - GRAM-06: Custom dictionary suppresses false positive

    @Test("adding word to dictionary suppresses spelling error on re-check")
    func customDictionarySuppression() async {
        let service = makeService()

        let before = await service.check(text: "I love this prodcut very much.")
        let spellingBefore = before.filter { $0.category == .spelling && $0.original.lowercased().contains("prodcut") }
        #expect(!spellingBefore.isEmpty, "Expected spelling error for 'prodcut' before adding to dictionary")

        await service.addToDictionary(word: "prodcut")

        let after = await service.check(text: "I love this prodcut very much.")
        let spellingAfter = after.filter { $0.category == .spelling && $0.original.lowercased().contains("prodcut") }
        #expect(spellingAfter.isEmpty, "Expected no spelling error for 'prodcut' after adding to dictionary")
    }

    // MARK: - GRAM-08: Dialect switching

    @Test("initializes with British dialect without crash and returns results")
    func dialectSwitchingGB() async {
        let service = makeService(dialect: "GB")
        let suggestions = await service.check(text: "I love this prodcut very much.")
        #expect(!suggestions.isEmpty, "Expected spelling suggestions even with GB dialect")
    }

    @Test("initializes with various dialects without crash")
    func dialectVariants() async {
        for dialect in ["US", "GB", "AU", "CA"] {
            let service = makeService(dialect: dialect)
            let suggestions = await service.check(text: "I love this prodcut very much.")
            #expect(!suggestions.isEmpty, "Expected results for dialect \(dialect)")
        }
    }

    // MARK: - GRAM-09: Rule toggling

    @Test("disabling SpellCheck rule suppresses spelling suggestions")
    func ruleTogglingSpellCheck() async {
        let service = makeService()

        let before = await service.check(text: "I love this prodcut very much.")
        let spellingBefore = before.filter { $0.category == .spelling }
        #expect(!spellingBefore.isEmpty, "Expected spelling suggestions before disabling SpellCheck")

        await service.setRuleEnabled(key: "SpellCheck", enabled: false)

        let after = await service.check(text: "I love this prodcut very much.")
        let spellingAfter = after.filter { $0.category == .spelling }
        #expect(spellingAfter.isEmpty, "Expected no spelling suggestions after disabling SpellCheck")
    }

    @Test("re-enabling SpellCheck rule restores spelling suggestions")
    func ruleTogglingReEnable() async {
        let service = makeService()

        await service.setRuleEnabled(key: "SpellCheck", enabled: false)
        let disabled = await service.check(text: "I love this prodcut very much.")
        let spellingDisabled = disabled.filter { $0.category == .spelling }
        #expect(spellingDisabled.isEmpty, "Expected no spelling suggestions with SpellCheck disabled")

        await service.setRuleEnabled(key: "SpellCheck", enabled: true)
        let reEnabled = await service.check(text: "I love this prodcut very much.")
        let spellingReEnabled = reEnabled.filter { $0.category == .spelling }
        #expect(!spellingReEnabled.isEmpty, "Expected spelling suggestions restored after re-enabling SpellCheck")
    }

    @Test("disabling RepeatedWords rule suppresses repeated word suggestions")
    func ruleTogglingRepeatedWords() async {
        let service = makeService()
        let text = "I went to to the store."

        let before = await service.check(text: text)
        let repeatedBefore = before.filter { $0.original.lowercased() == "to" || $0.message.lowercased().contains("repeat") }

        await service.setRuleEnabled(key: "RepeatedWords", enabled: false)
        let after = await service.check(text: text)
        let repeatedAfter = after.filter { $0.original.lowercased() == "to" || $0.message.lowercased().contains("repeat") }

        if !repeatedBefore.isEmpty {
            #expect(repeatedAfter.count < repeatedBefore.count, "Expected fewer repeated-word suggestions after disabling RepeatedWords")
        }
    }

    // MARK: - CLAR-08 / CLAR-18: Severity filter (Swift post-processing)

    private func makeClaritySuggestion(severity: Severity) -> Suggestion {
        let text = "x"
        let range = text.startIndex..<text.endIndex
        return Suggestion(
            id: UUID(),
            range: range,
            original: "x",
            primaryReplacement: "y",
            allReplacements: ["y"],
            message: "synthetic",
            category: .clarity,
            source: .harper,
            priority: 200,
            paragraphHash: nil,
            severity: severity
        )
    }

    private func makeSpellingSuggestion(severity: Severity?) -> Suggestion {
        let text = "x"
        let range = text.startIndex..<text.endIndex
        return Suggestion(
            id: UUID(),
            range: range,
            original: "x",
            primaryReplacement: "y",
            allReplacements: ["y"],
            message: "synthetic",
            category: .spelling,
            source: .harper,
            priority: 60,
            paragraphHash: nil,
            severity: severity
        )
    }

    @Test("severity filter drops low clarity when opinionated flag is off")
    func severityFilter_dropsLowWhenOpinionatedOff() {
        let high = makeClaritySuggestion(severity: .high)
        let medium = makeClaritySuggestion(severity: .medium)
        let low = makeClaritySuggestion(severity: .low)
        let spelling = makeSpellingSuggestion(severity: nil)

        let kept = [high, medium, low, spelling].filter {
            !HarperService.shouldDropClarityLow($0, opinionatedEnabled: false)
        }
        #expect(kept.count == 3)
        #expect(!kept.contains(where: { $0.id == low.id }))
    }

    @Test("severity filter keeps low clarity when opinionated flag is on")
    func severityFilter_keepsLowWhenOpinionatedOn() {
        let high = makeClaritySuggestion(severity: .high)
        let medium = makeClaritySuggestion(severity: .medium)
        let low = makeClaritySuggestion(severity: .low)
        let spelling = makeSpellingSuggestion(severity: nil)

        let kept = [high, medium, low, spelling].filter {
            !HarperService.shouldDropClarityLow($0, opinionatedEnabled: true)
        }
        #expect(kept.count == 4)
    }

    @Test("severity filter never drops high or medium clarity")
    func severityFilter_keepsHighAndMediumAlways() {
        let high = makeClaritySuggestion(severity: .high)
        let medium = makeClaritySuggestion(severity: .medium)
        for opin in [false, true] {
            #expect(HarperService.shouldDropClarityLow(high, opinionatedEnabled: opin) == false)
            #expect(HarperService.shouldDropClarityLow(medium, opinionatedEnabled: opin) == false)
        }
    }

    @Test("severity filter never touches non-clarity suggestions even with low severity")
    func severityFilter_neverTouchesSpellingOrGrammar() {
        // Synthetic spelling-with-low-severity (Harper does not actually emit this,
        // but the predicate must guard both source AND category, not just severity).
        let lowSpelling = makeSpellingSuggestion(severity: .low)
        #expect(HarperService.shouldDropClarityLow(lowSpelling, opinionatedEnabled: false) == false)
    }

    // MARK: - CLAR-07: per-rule toggle for WordyPhrases (mirror ruleTogglingSpellCheck)

    @Test("disabling WordyPhrases rule suppresses clarity suggestions")
    func ruleTogglingWordyPhrases() async {
        let service = makeService()
        let text = "Please utilize this for users."

        let before = await service.check(text: text)
        let clarityBefore = before.filter { $0.category == .clarity }
        #expect(!clarityBefore.isEmpty, "Expected clarity suggestions before disabling WordyPhrases")

        await service.setRuleEnabled(key: "WordyPhrases", enabled: false)
        let after = await service.check(text: text)
        let clarityAfter = after.filter { $0.category == .clarity }
        #expect(clarityAfter.isEmpty, "Expected no clarity suggestions after disabling WordyPhrases")

        await service.setRuleEnabled(key: "WordyPhrases", enabled: true)
        let restored = await service.check(text: text)
        let clarityRestored = restored.filter { $0.category == .clarity }
        #expect(!clarityRestored.isEmpty, "Expected clarity suggestions restored after re-enabling")
    }
}
