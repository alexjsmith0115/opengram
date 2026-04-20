import Testing
@testable import OpenGramLib

@Suite("RephraseCardViewModel.headerText")
struct RephraseCardViewModelTests {

    @Test func clarityOnly_returnsImproveClarity() {
        let out = RephraseCardViewModel.headerText(for: [.clarity])
        #expect(out == "Improve clarity")
    }

    @Test func rephraseOnly_returnsImproveClarity() {
        let out = RephraseCardViewModel.headerText(for: [.rephrase])
        #expect(out == "Improve clarity")
    }

    @Test func toneOnly_direct_returnsEmpty() {
        // .tone is collapsed to .clarity by checkCategory(from:) at call-sites; a
        // raw .tone passed directly to headerText is treated like spelling — folds
        // silently (not a clarity/grammar signal on its own).
        let out = RephraseCardViewModel.headerText(for: [.tone])
        #expect(out == "")
    }

    @Test func grammarOnly_returnsFixGrammar() {
        let out = RephraseCardViewModel.headerText(for: [.grammarPunctuation])
        #expect(out == "Fix grammar")
    }

    @Test func clarityAndGrammar_returnsBoth() {
        let out = RephraseCardViewModel.headerText(for: [.clarity, .grammarPunctuation])
        #expect(out == "Improve clarity and fix grammar")
    }

    @Test func spellingOnly_returnsEmpty() {
        // Spelling folds silently — with no clarity and no grammar, result is empty.
        let out = RephraseCardViewModel.headerText(for: [.spelling])
        #expect(out == "")
    }

    @Test func spellingPlusClarity_returnsImproveClarity() {
        let out = RephraseCardViewModel.headerText(for: [.spelling, .clarity])
        #expect(out == "Improve clarity")
    }

    @Test func empty_returnsEmpty() {
        #expect(RephraseCardViewModel.headerText(for: []) == "")
    }

    @Test func categoryMap_rephrase() {
        #expect(RephraseCardViewModel.checkCategory(from: .rephrase) == .rephrase)
    }

    @Test func categoryMap_tone_collapsesToClarity() {
        // .tone → .clarity (tone adjustments are a clarity concern for the header)
        #expect(RephraseCardViewModel.checkCategory(from: .tone) == .clarity)
    }
}
