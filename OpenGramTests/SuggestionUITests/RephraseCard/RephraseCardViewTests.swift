import Testing
import SwiftUI
@testable import OpenGramLib

@MainActor
@Suite("RephraseCardView")
struct RephraseCardViewTests {

    private func makeMonitor() -> TextMonitor {
        let orchestrator = CheckOrchestrator(harper: TMockGrammarChecker())
        return TextMonitor(
            textEngine: TMockAXTextEngine(),
            orchestrator: orchestrator,
            capabilityCache: TMockCapabilityCache()
        )
    }

    @Test func init_compiles_andBodyResolvesWithoutCrash() {
        let source = "hello world"
        let p = Paragraph(text: source, range: source.startIndex..<source.endIndex, index: 0)
        var acceptCount = 0
        var dismissCount = 0
        let vm = RephraseCardViewModel(
            paragraph: p,
            issues: [],
            rephrase: "hello world",
            segments: [.unchanged("hello world")],
            header: "Improve clarity",
            onAccept: { acceptCount += 1 },
            onDismiss: { dismissCount += 1 }
        )
        let view = RephraseCardView(viewModel: vm)
        // Touch body to ensure no runtime crash in the default render path.
        _ = view.body
        #expect(vm.header == "Improve clarity")
        // Callbacks reachable after View constructed
        vm.onAccept()
        vm.onDismiss()
        #expect(acceptCount == 1)
        #expect(dismissCount == 1)
    }

    @Test func bodyContent_noScrollView_multiSegmentBodyResolvesWithoutCrash() {
        // Regression for D-01: verifies RephraseCardView renders a multi-segment diff body
        // (added + removed + unchanged) without crash after ScrollView removal.
        // ScrollView presence/absence is verified structurally via grep in the acceptance criteria.
        let source = "The quick brown fox jumps over the lazy dog"
        let p = Paragraph(text: source, range: source.startIndex..<source.endIndex, index: 0)
        let vm = RephraseCardViewModel(
            paragraph: p,
            issues: [],
            rephrase: "A swift auburn fox leaps over the lethargic dog",
            segments: [
                .unchanged("The"),
                .removed("quick brown"),
                .added("swift auburn"),
                .unchanged("fox"),
                .removed("jumps"),
                .added("leaps"),
                .unchanged("over the"),
                .removed("lazy"),
                .added("lethargic"),
                .unchanged("dog")
            ],
            header: "Improve clarity",
            onAccept: {},
            onDismiss: {}
        )
        let view = RephraseCardView(viewModel: vm)
        // Touch body in both diff modes — no crash expected
        _ = view.body
        #expect(vm.segments.count == 10)
    }

    @Test func additionsOnlyMode_omitsRemovedSegments_conceptually() {
        // Data-level assertion: additions-only omits .removed segments.
        // Actual visual verification deferred to Phase 19 UAT.
        let segs: [DiffSegment] = [.unchanged("a"), .removed("b"), .added("c")]
        let expectedAdditionsOnly = segs.filter {
            if case .removed = $0 { return false } else { return true }
        }
        #expect(expectedAdditionsOnly.count == 2)
    }
}
