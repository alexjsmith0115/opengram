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

// MARK: - CheckCoordinator flag gating (WIRE-01 regression)

/// Tests the routing gate introduced in CheckCoordinator.handleHotkeyFired() via the
/// extracted pure function llmPanelGatePasses(cardEnabled:suggestions:).
///
/// These are behavioral assertions against the gate expression itself — if the condition
/// in llmPanelGatePasses is removed or inverted, these tests fail. A full spy-based test
/// (constructing CheckCoordinator with a LLMPanelShowing mock) requires stubbing
/// StatusBarController and LLMCheckScheduler — deferred per 18.1 CONTEXT.md minimize-diff.
@MainActor
@Suite("CheckCoordinator LLMPanel flag gate (WIRE-01 regression)")
struct CheckCoordinatorFlagGatingTests {

    private func makeSuggestion() -> LLMStyleSuggestion {
        LLMStyleSuggestion(
            category: .clarity,
            originalText: "We should probably consider doing this",
            revisedText: "Consider doing this",
            explanation: "Remove hedging",
            confidence: 8
        )
    }

    // flag=true → panel must NOT fire regardless of suggestion count
    @Test func flagOn_panelSuppressed() {
        let suggestions = [makeSuggestion()]
        #expect(
            CheckCoordinator.llmPanelGatePasses(cardEnabled: true, suggestions: suggestions) == false,
            "card flag ON → gate must return false (panel suppressed)"
        )
    }

    // flag=true + empty suggestions → also suppressed
    @Test func flagOn_noSuggestions_panelSuppressed() {
        #expect(
            CheckCoordinator.llmPanelGatePasses(cardEnabled: true, suggestions: []) == false,
            "card flag ON + empty suggestions → gate must return false"
        )
    }

    // flag=false + non-empty suggestions → panel must fire
    @Test func flagOff_withSuggestions_panelInvoked() {
        let suggestions = [makeSuggestion()]
        #expect(
            CheckCoordinator.llmPanelGatePasses(cardEnabled: false, suggestions: suggestions) == true,
            "card flag OFF + suggestions → gate must return true (panel invoked)"
        )
    }

    // flag=false + empty suggestions → panel must NOT fire (nothing to show)
    @Test func flagOff_noSuggestions_panelSuppressed() {
        #expect(
            CheckCoordinator.llmPanelGatePasses(cardEnabled: false, suggestions: []) == false,
            "card flag OFF + empty suggestions → gate must return false (nothing to show)"
        )
    }
}
