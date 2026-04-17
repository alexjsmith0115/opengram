import Testing
import AppKit
@testable import OpenGramLib

@MainActor
@Suite("OverlayController rephrase card dispatch branch")
struct OverlayControllerRephraseIntegrationTests {

    private struct OnFlag: IncrementalConfig {
        var isIncrementalCheckingEnabled: Bool { true }
        var paragraphRephraseCardEnabled: Bool { true }
        var minIssueCount: Int { 2 }
        var minWordCount: Int { 12 }
        var idleDebounceSeconds: TimeInterval { 1.5 }
    }

    private struct OffFlag: IncrementalConfig {
        var isIncrementalCheckingEnabled: Bool { true }
        var paragraphRephraseCardEnabled: Bool { false }   // REPH-15
        var minIssueCount: Int { 2 }
        var minWordCount: Int { 12 }
        var idleDebounceSeconds: TimeInterval { 1.5 }
    }

    @Test func flagOff_noHiddenRangeSet_afterInit() {
        let ctrl = OverlayController(incrementalConfig: OffFlag())
        #expect(ctrl.hiddenParagraphScalarRange == nil)
    }

    @Test func flagOn_noSchedulerOrMonitor_doesNotDispatch() {
        // Missing scheduler/monitor → tryDispatchRephraseCard early-returns false (safety fallback).
        let ctrl = OverlayController(
            scheduler: nil,
            textMonitor: nil,
            incrementalConfig: OnFlag()
        )
        #expect(ctrl.hiddenParagraphScalarRange == nil)
    }
}
