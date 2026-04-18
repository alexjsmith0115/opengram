import Testing
import Foundation
@testable import OpenGramLib

@Suite struct OpenGramConfigTests {
    private func makeSuite(_ name: String = UUID().uuidString) -> UserDefaults {
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return suite
    }

    // MARK: Defaults

    @Test func defaultsMatchContextSpec() {
        let cfg = OpenGramConfig(defaults: makeSuite())
        #expect(cfg.harperDebounceMs == 300)
        #expect(cfg.llmDebounceMs == 2000)
        #expect(cfg.llmRequestTimeoutSeconds == 30)
        #expect(cfg.minParagraphLength == 30)
        #expect(cfg.minParagraphWordCount == 2)
    }

    @Test func phase17KeysAbsorbedAtSameDefaults() {
        let cfg = OpenGramConfig(defaults: makeSuite())
        #expect(cfg.minIssueCount == 2)
        #expect(cfg.minWordCount == 12)
        #expect(cfg.idleDebounceSeconds == 1.5)
    }

    // MARK: Live read (no snapshot)

    @Test func liveReadReflectsUpdatesOnSameInstance() {
        let suite = makeSuite()
        let cfg = OpenGramConfig(defaults: suite)
        #expect(cfg.minParagraphLength == 30)
        suite.set(7, forKey: OpenGramConfig.minParagraphLengthKey)
        #expect(cfg.minParagraphLength == 7)
    }

    @Test func distinguishesUnsetFromUserSetZero() {
        let suite = makeSuite()
        let cfg = OpenGramConfig(defaults: suite)
        #expect(cfg.minParagraphLength == 30)   // unset → default
        suite.set(0, forKey: OpenGramConfig.minParagraphLengthKey)
        #expect(cfg.minParagraphLength == 0)    // user-set zero — NOT default
    }

    @Test func timeIntervalReadsAsDouble() {
        let suite = makeSuite()
        let cfg = OpenGramConfig(defaults: suite)
        suite.set(5.5, forKey: OpenGramConfig.idleDebounceSecondsKey)
        #expect(cfg.idleDebounceSeconds == 5.5)
    }

    // MARK: Change notification

    @Test func postDidChangeDeliversToObserver() async {
        // Use an isolated center so this test doesn't fire listeners in other test suites
        // that may be observing NotificationCenter.default for the same name.
        let center = NotificationCenter()
        let received = await withCheckedContinuation { continuation in
            let observer = center.addObserver(
                forName: OpenGramConfig.didChangeNotification,
                object: nil,
                queue: nil
            ) { _ in
                continuation.resume(returning: true)
            }
            OpenGramConfig.postDidChange(to: center)
            _ = observer  // retain until fired
        }
        #expect(received == true)
    }

    // MARK: Key-literal contract (matches @AppStorage in AdvancedSettingsView)

    @Test func absorbedKeyLiteralsMatchPhase17() {
        #expect(OpenGramConfig.minIssueCountKey == "llmMinIssueCount")
        #expect(OpenGramConfig.minWordCountKey == "llmMinWordCount")
        #expect(OpenGramConfig.idleDebounceSecondsKey == "llmIdleDebounceSeconds")
    }
}
