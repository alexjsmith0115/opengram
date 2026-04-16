import Testing
import Foundation
@testable import OpenGramLib

@Suite @MainActor struct AdvancedSettingsViewTests {
    private func makeSuite(_ name: String = UUID().uuidString) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    @Test func warningText_matchesSpec() {
        let expected = "Advanced settings are unstable \u{2014} values may change between versions."
        #expect(AdvancedSettingsView.warningText == expected)
    }

    @Test func appStorageKeys_matchIncrementalConfigKeys() {
        #expect(AdvancedSettingsView.minIssueCountKey == "llmMinIssueCount")
        #expect(AdvancedSettingsView.minWordCountKey == "llmMinWordCount")
        #expect(AdvancedSettingsView.idleDebounceSecondsKey == "llmIdleDebounceSeconds")
    }

    @Test func resetDefaults_writesLockedDefaultsToSuite() {
        let suite = makeSuite()
        suite.set(7, forKey: "llmMinIssueCount")
        suite.set(30, forKey: "llmMinWordCount")
        suite.set(4.0, forKey: "llmIdleDebounceSeconds")

        AdvancedSettingsView.resetDefaults(in: suite)

        let cfg = UserDefaultsIncrementalConfig(defaults: suite)
        #expect(cfg.minIssueCount == UserDefaultsIncrementalConfig.defaultMinIssueCount)
        #expect(cfg.minWordCount == UserDefaultsIncrementalConfig.defaultMinWordCount)
        #expect(cfg.idleDebounceSeconds == UserDefaultsIncrementalConfig.defaultIdleDebounceSeconds)
        #expect(cfg.minIssueCount == 2)
        #expect(cfg.minWordCount == 12)
        #expect(cfg.idleDebounceSeconds == 1.5)
    }

    @Test func defaultLiterals_matchStaticDefaults() {
        #expect(UserDefaultsIncrementalConfig.defaultMinIssueCount == 2)
        #expect(UserDefaultsIncrementalConfig.defaultMinWordCount == 12)
        #expect(UserDefaultsIncrementalConfig.defaultIdleDebounceSeconds == 1.5)
    }
}
