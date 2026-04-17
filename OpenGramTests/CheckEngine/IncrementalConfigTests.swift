import Testing
import Foundation
@testable import OpenGramLib

@Suite struct IncrementalConfigTests {
    private func makeSuite(_ name: String = UUID().uuidString) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func defaults_returnDefaultsWhenUnset() {
        let suite = makeSuite()
        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.minIssueCount == 2)
        #expect(cfg.minWordCount == 12)
        #expect(cfg.idleDebounceSeconds == 1.5)
    }

    @Test func defaults_returnUserDefinedValues() {
        let suite = makeSuite()
        suite.set(4, forKey: "llmMinIssueCount")
        suite.set(20, forKey: "llmMinWordCount")
        suite.set(3.0, forKey: "llmIdleDebounceSeconds")
        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.minIssueCount == 4)
        #expect(cfg.minWordCount == 20)
        #expect(cfg.idleDebounceSeconds == 3.0)
    }

    @Test func defaults_liveReadReflectsUpdatesOnSameInstance() {
        let suite = makeSuite()
        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.minIssueCount == 2)
        suite.set(7, forKey: "llmMinIssueCount")
        #expect(cfg.minIssueCount == 7)
        suite.set(0.5, forKey: "llmIdleDebounceSeconds")
        #expect(cfg.idleDebounceSeconds == 0.5)
    }

    @Test func staticDefaults_matchLockedValues() {
        #expect(UserDefaultsIncrementalConfig.defaultMinIssueCount == 2)
        #expect(UserDefaultsIncrementalConfig.defaultMinWordCount == 12)
        #expect(UserDefaultsIncrementalConfig.defaultIdleDebounceSeconds == 1.5)
    }

    @Test func zeroValueDistinguishedFromUnset() {
        let suite = makeSuite()
        suite.set(0, forKey: "llmMinIssueCount")
        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.minIssueCount == 0)
    }

    @Test func paragraphRephraseCardEnabled_defaultFalse_whenUnset() {
        let suite = makeSuite()
        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.paragraphRephraseCardEnabled == false)
    }

    @Test func paragraphRephraseCardEnabled_true_whenSet() {
        let suite = makeSuite()
        suite.set(true, forKey: UserDefaultsIncrementalConfig.paragraphRephraseCardEnabledKey)
        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.paragraphRephraseCardEnabled == true)
    }

    @Test func paragraphRephraseCardEnabledKey_matchesExpectedString() {
        #expect(UserDefaultsIncrementalConfig.paragraphRephraseCardEnabledKey == "llmParagraphRephraseCardEnabled")
    }
}
