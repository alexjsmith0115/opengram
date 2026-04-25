import Testing
import Foundation
@testable import OpenGramLib

@Suite @MainActor struct ClaritySettingsViewTests {

    @Test func appStorageKeys_matchLiterals() {
        #expect(ClaritySettingsView.clarityEnabledKey == "clarityEnabled")
        #expect(ClaritySettingsView.clarityOpinionatedEnabledKey == "clarityOpinionatedEnabled")
    }

    @Test func defaults_matchLockedValues() {
        #expect(ClaritySettingsView.defaultClarityEnabled == true)
        #expect(ClaritySettingsView.defaultClarityOpinionatedEnabled == false)
    }

    @Test func notifyMasterChanged_postsNotification() async {
        let center = NotificationCenter()
        var fired = false
        let obs = center.addObserver(
            forName: .clarityMasterDidChange, object: nil, queue: nil
        ) { _ in fired = true }
        defer { center.removeObserver(obs) }

        ClaritySettingsView.notifyMasterChanged(center: center)
        #expect(fired == true)
    }

    @Test func subToggle_disabledWhenMasterOff() {
        // UI-SPEC §Validation Hooks #2: sub-toggle is disabled when master OFF.
        // ClaritySettingsView.body applies `.disabled(!clarityEnabled)` to the sub-toggle;
        // this asserts the underlying predicate via the testable static helper.
        #expect(ClaritySettingsView.isSubToggleDisabled(masterOn: false) == true)
        #expect(ClaritySettingsView.isSubToggleDisabled(masterOn: true) == false)
    }
}
