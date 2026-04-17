import Testing
@preconcurrency import ApplicationServices
import AppKit
@testable import OpenGramLib

@MainActor
@Suite("RephraseCardPanelController")
struct RephraseCardPanelControllerTests {

    private func makeMonitor() -> TextMonitor {
        let orchestrator = CheckOrchestrator(harper: TMockGrammarChecker(), llm: nil)
        return TextMonitor(
            textEngine: TMockAXTextEngine(),
            orchestrator: orchestrator,
            capabilityCache: TMockCapabilityCache()
        )
    }

    private func makeViewModel() -> RephraseCardViewModel {
        let source = "hello"
        let p = Paragraph(text: source, range: source.startIndex..<source.endIndex, index: 0)
        return RephraseCardViewModel(
            paragraph: p,
            issues: [],
            rephrase: "hello",
            segments: [.unchanged("hello")],
            header: "Improve clarity",
            onAccept: {},
            onDismiss: {}
        )
    }

    @Test func hide_isIdempotent() {
        let ctrl = RephraseCardPanelController()
        ctrl.hide()   // before show — must not crash
        ctrl.hide()   // double-call — must not crash
    }

    @Test func show_thenHide_firesOnHideCallback() async {
        let ctrl = RephraseCardPanelController()
        var hideCount = 0

        let monitor = makeMonitor()
        guard let screen = NSScreen.main else { return }

        ctrl.show(
            viewModel: makeViewModel(),
            near: NSRect(x: 100, y: 100, width: 200, height: 40),
            on: screen,
            axElement: AXUIElementCreateSystemWide(),
            paragraphScalarRange: (scalarStart: 0, scalarLength: 5),
            textMonitor: monitor,
            onHide: { hideCount += 1 }
        )

        ctrl.hide()
        #expect(hideCount == 1)
    }

    @Test func keystroke_subscription_installsAndRestoresCleanly() async {
        // Verifies that after show(), monitor.onKeystroke is non-nil (subscription installed),
        // and after hide() it is restored to nil (previous value before show).
        let ctrl = RephraseCardPanelController()
        var hideCount = 0

        let monitor = makeMonitor()
        guard let screen = NSScreen.main else { return }

        ctrl.show(
            viewModel: makeViewModel(),
            near: NSRect(x: 100, y: 100, width: 200, height: 40),
            on: screen,
            axElement: AXUIElementCreateSystemWide(),
            paragraphScalarRange: (scalarStart: 0, scalarLength: 5),
            textMonitor: monitor,
            onHide: { hideCount += 1 }
        )

        // Subscription installed.
        #expect(monitor.onKeystroke != nil)

        ctrl.hide()

        // Subscription restored to prior value (nil — no prior subscriber).
        #expect(monitor.onKeystroke == nil)
        #expect(hideCount == 1)
    }
}
