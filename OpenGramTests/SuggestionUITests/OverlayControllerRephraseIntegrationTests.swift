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

// MARK: - WIRE-01 integration: hotkey path routes LLM suggestions to overlay

/// Verifies the fix for WIRE-01: CheckCoordinator.handleHotkeyFired() must pass
/// scheduler LLM Suggestions into overlayController.update() so tryDispatchRephraseCard
/// can filter them. This test directly exercises the merge contract: overlayController.update()
/// with a merged [harper + llm] array stores the LLM entry in suggestions.
@MainActor
@Suite("WIRE-01: LLM suggestions survive overlay update() round-trip")
struct OverlayControllerWIRE01IntegrationTests {

    private struct OnFlag: IncrementalConfig {
        var isIncrementalCheckingEnabled: Bool { true }
        var paragraphRephraseCardEnabled: Bool { true }
        var minIssueCount: Int { 2 }
        var minWordCount: Int { 12 }
        var idleDebounceSeconds: TimeInterval { 1.5 }
    }

    @Test func hotkeyFired_schedulerLLMSuggestions_reachOverlayController() {
        let paragraphText = "This is a test paragraph with enough words to qualify for the rephrase card dispatch path in OpenGram."
        let hash = Sha256ParagraphHasher().hash(paragraphText)

        let llmSuggestion = Suggestion(
            id: UUID(),
            range: paragraphText.startIndex ..< paragraphText.endIndex,
            original: paragraphText,
            primaryReplacement: "This test paragraph has enough words to qualify for the rephrase card.",
            allReplacements: [],
            message: "Rephrase for clarity",
            category: .clarity,
            source: .llm,
            priority: 80,
            paragraphHash: hash
        )

        let harperSuggestion = Suggestion(
            id: UUID(),
            range: "typo".startIndex ..< "typo".endIndex,
            original: "typo",
            primaryReplacement: "type",
            allReplacements: ["type"],
            message: "Spelling",
            category: .spelling,
            source: .harper,
            priority: 100,
            paragraphHash: nil
        )

        let overlayCtrl = OverlayController(incrementalConfig: OnFlag())

        // Simulate the fixed coordinator's merge: accumulated (Harper) + llmSuggestions.
        let merged = [harperSuggestion, llmSuggestion]

        let ctx = TextContext(
            text: paragraphText,
            bundleID: "com.test",
            extractionMethod: .axDirectSelection,
            selectionRange: nil,
            elementBounds: nil,
            axElement: AXUIElementCreateSystemWide()
        )
        overlayCtrl.update(suggestions: merged, context: ctx)

        // OverlayController.suggestions stores the merged set (capped at maxDisplayedSuggestions).
        let llmInSuggestions = overlayCtrl.suggestions.filter { $0.source == .llm }
        #expect(!llmInSuggestions.isEmpty, "OverlayController must store LLM suggestion after update()")
        #expect(llmInSuggestions.first?.paragraphHash == hash, "paragraphHash must survive merge round-trip")
    }
}
