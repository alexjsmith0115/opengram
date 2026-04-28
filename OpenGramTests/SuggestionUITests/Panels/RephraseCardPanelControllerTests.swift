import Testing
@preconcurrency import ApplicationServices
import AppKit
import SwiftUI
@testable import OpenGramLib

@MainActor
@Suite("RephraseCardPanelController")
struct RephraseCardPanelControllerTests {

    private func makeMonitor() -> TextMonitor {
        let orchestrator = CheckOrchestrator(harper: TMockGrammarChecker())
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

    private func makeLongViewModel() -> RephraseCardViewModel {
        // Force intrinsic height > visibleFrame.height - 40 via a single very long unchanged segment.
        // ~8000 chars wraps into far more lines than any reasonable screen accommodates.
        let longText = String(repeating: "This is a long rephrase rationale that wraps over many lines. ", count: 120)
        let source = longText
        let p = Paragraph(text: source, range: source.startIndex..<source.endIndex, index: 0)
        return RephraseCardViewModel(
            paragraph: p,
            issues: [],
            rephrase: longText,
            segments: [.unchanged(longText)],
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

    // MARK: - D-11 sizing / overflow

    @Test func show_shortContent_installsPlainHostingView() async {
        let ctrl = RephraseCardPanelController()
        let monitor = makeMonitor()
        guard let screen = NSScreen.main else { return }

        ctrl.show(
            viewModel: makeViewModel(),
            near: NSRect(x: 100, y: 100, width: 200, height: 40),
            on: screen,
            axElement: AXUIElementCreateSystemWide(),
            paragraphScalarRange: (scalarStart: 0, scalarLength: 5),
            textMonitor: monitor,
            onHide: {}
        )

        let panel = ctrl.testHookPanel
        #expect(panel != nil)
        #expect(panel?.contentView is NSHostingView<RephraseCardView>)
        #expect(panel?.backgroundColor == .clear)
        #expect(panel?.isOpaque == false)
        #expect(panel?.hasShadow == false)

        let visibleFrame = screen.visibleFrame
        #expect((panel?.frame.height ?? 0) >= 140)
        #expect((panel?.frame.height ?? 0) <= visibleFrame.height - 40)

        ctrl.hide()
    }

    @Test func show_longContent_installsScrollWrapper_andCapsHeight() async {
        let ctrl = RephraseCardPanelController()
        let monitor = makeMonitor()
        guard let screen = NSScreen.main else { return }

        // Headless NSHostingView always returns idealHeight; inject an oversized fitting size
        // so the overflow branch fires deterministically without a real display.
        ctrl.testHookFittingSize = NSSize(width: 380, height: screen.visibleFrame.height + 500)

        ctrl.show(
            viewModel: makeLongViewModel(),
            near: NSRect(x: 100, y: 100, width: 200, height: 40),
            on: screen,
            axElement: AXUIElementCreateSystemWide(),
            paragraphScalarRange: (scalarStart: 0, scalarLength: 5),
            textMonitor: monitor,
            onHide: {}
        )

        let panel = ctrl.testHookPanel
        #expect(panel != nil)
        #expect(panel?.contentView is NSScrollView)

        let visibleFrame = screen.visibleFrame
        #expect(panel?.frame.height == visibleFrame.height - 40)

        if let scroll = panel?.contentView as? NSScrollView {
            #expect(scroll.documentView is NSHostingView<RephraseCardView>)
            #expect(scroll.hasVerticalScroller == true)
            #expect(scroll.drawsBackground == false)
        } else {
            Issue.record("expected NSScrollView content view for long content")
        }

        ctrl.hide()
    }

    @Test func hide_afterLongContent_clearsPanelAndFiresOnHide() async {
        let ctrl = RephraseCardPanelController()
        var hideCount = 0
        let monitor = makeMonitor()
        guard let screen = NSScreen.main else { return }

        ctrl.testHookFittingSize = NSSize(width: 380, height: screen.visibleFrame.height + 500)

        ctrl.show(
            viewModel: makeLongViewModel(),
            near: NSRect(x: 100, y: 100, width: 200, height: 40),
            on: screen,
            axElement: AXUIElementCreateSystemWide(),
            paragraphScalarRange: (scalarStart: 0, scalarLength: 5),
            textMonitor: monitor,
            onHide: { hideCount += 1 }
        )
        #expect(ctrl.testHookPanel?.contentView is NSScrollView)

        ctrl.hide()
        #expect(ctrl.testHookPanel == nil)
        #expect(hideCount == 1)
    }
}
