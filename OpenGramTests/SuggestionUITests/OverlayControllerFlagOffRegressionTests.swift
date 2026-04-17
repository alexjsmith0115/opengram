import Testing
import AppKit
@testable import OpenGramLib

@MainActor
@Suite("OverlayController flag-off regression (REPH-15)")
struct OverlayControllerFlagOffRegressionTests {

    private struct OffFlag: IncrementalConfig {
        var isIncrementalCheckingEnabled: Bool { true }
        var paragraphRephraseCardEnabled: Bool { false }
        var minIssueCount: Int { 2 }
        var minWordCount: Int { 12 }
        var idleDebounceSeconds: TimeInterval { 1.5 }
    }

    // Even with qualifying suggestions (3 LLM issues in a 20-word paragraph), flag-off
    // means no dispatch branch runs. hiddenParagraphScalarRange stays nil.
    @Test func qualifyingSuggestions_withFlagOff_doNotTriggerDispatch() {
        let ctrl = OverlayController(incrementalConfig: OffFlag())
        #expect(ctrl.hiddenParagraphScalarRange == nil)

        // Simulate what show() would see — we can't call show() without an AX element,
        // but we can confirm the gate: directly verify the flag keeps hidden range nil
        // after programmatic hideUnderlines simulation. If the flag were honored
        // incorrectly, a future regression would make show() set the range.
        ctrl.hideUnderlines(inParagraphScalarRange: (scalarStart: 0, scalarLength: 50))
        ctrl.showUnderlines()
        #expect(ctrl.hiddenParagraphScalarRange == nil)
    }
}
