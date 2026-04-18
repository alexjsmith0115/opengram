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

    @Test func appStorageKeys_matchConfigLiterals() {
        #expect(AdvancedSettingsView.minIssueCountKey == "llmMinIssueCount")
        #expect(AdvancedSettingsView.minWordCountKey == "llmMinWordCount")
        #expect(AdvancedSettingsView.idleDebounceSecondsKey == "llmIdleDebounceSeconds")
    }

    /// Drift guard: `@AppStorage` property wrappers in `AdvancedSettingsView` use string
    /// literals (property wrapper arguments must be compile-time constants). This test
    /// asserts the view's key constants match `OpenGramConfig`'s keys so
    /// a rename on one side forces a rename on the other.
    @Test func appStorageKeys_matchConfigKeys() {
        #expect(AdvancedSettingsView.minIssueCountKey == OpenGramConfig.minIssueCountKey)
        #expect(AdvancedSettingsView.minWordCountKey == OpenGramConfig.minWordCountKey)
        #expect(AdvancedSettingsView.idleDebounceSecondsKey == OpenGramConfig.idleDebounceSecondsKey)
    }

    @Test func resetDefaults_writesLockedDefaultsToSuite() {
        let suite = makeSuite()
        suite.set(7, forKey: "llmMinIssueCount")
        suite.set(30, forKey: "llmMinWordCount")
        suite.set(4.0, forKey: "llmIdleDebounceSeconds")

        AdvancedSettingsView.resetDefaults(in: suite)

        let cfg = OpenGramConfig(defaults: suite)
        #expect(cfg.minIssueCount == OpenGramConfig.defaultMinIssueCount)
        #expect(cfg.minWordCount == OpenGramConfig.defaultMinWordCount)
        #expect(cfg.idleDebounceSeconds == OpenGramConfig.defaultIdleDebounceSeconds)
        #expect(cfg.minIssueCount == 2)
        #expect(cfg.minWordCount == 12)
        #expect(cfg.idleDebounceSeconds == 1.5)
    }

    @Test func defaultLiterals_matchStaticDefaults() {
        #expect(OpenGramConfig.defaultMinIssueCount == 2)
        #expect(OpenGramConfig.defaultMinWordCount == 12)
        #expect(OpenGramConfig.defaultIdleDebounceSeconds == 1.5)
    }

    @Test func resetDefaults_postsDidChangeNotification() async {
        let suite = makeSuite()
        let center = NotificationCenter()
        var fired = false
        let obs = center.addObserver(
            forName: OpenGramConfig.didChangeNotification,
            object: nil, queue: nil
        ) { _ in fired = true }
        defer { center.removeObserver(obs) }

        AdvancedSettingsView.resetDefaults(in: suite, center: center)

        #expect(fired == true)
    }
}
