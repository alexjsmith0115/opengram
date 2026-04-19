import Testing
import AppKit
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

@Suite("OverlayController scroll mode")
@MainActor
struct OverlayControllerScrollModeTests {

    // MARK: helpers

    private func makeController() -> OverlayController {
        let mock = MockAXAccessor()
        return OverlayController(accessor: mock, axQueue: AXCallQueue(accessor: mock))
    }

    private func makeContext(bundleID: String) -> TextContext {
        TextContext(
            text: "sample text",
            bundleID: bundleID,
            extractionMethod: .axDirectSelection,
            selectionRange: nil,
            elementBounds: CGRect(x: 0, y: 0, width: 400, height: 300),
            axElement: AXUIElementCreateSystemWide()
        )
    }

    // MARK: PERF-07 — mode resolution (Tests 1-2)

    @Test("unknown bundle defaults to hideAndSettle")
    func unknownBundleDefault() {
        let c = makeController()
        #expect(c.resolveScrollMode(bundleID: "com.unknown.app") == .hideAndSettle)
    }

    @Test("com.apple.Notes resolves to trackFrame")
    func notesIsTrackFrame() {
        let c = makeController()
        #expect(c.resolveScrollMode(bundleID: "com.apple.Notes") == .trackFrame)
    }

    // MARK: PERF-08 — hideAndSettle fade + settle (Tests 3-4)

    @Test("hideAndSettle scroll event fades underlines to 0 and sets .faded")
    func hideAndSettle_fadesOnScroll() async {
        let c = makeController()
        // underlineView is internal (var) per D-27 — set directly so fadeUnderlines
        // has a target and alpha is observable.
        let view = UnderlineView()
        view.alphaValue = 1
        c.underlineView = view
        c.effectiveScrollMode = .hideAndSettle

        c.handleScrollEvent()

        #expect(c.scrollState == .faded)
        // NSAnimationContext.runAnimationGroup drives the animator proxy, which
        // updates the model alphaValue asynchronously on the main run loop.
        // Poll briefly (fade duration is 0.08s) instead of sampling synchronously.
        let deadline = Date().addingTimeInterval(1.0)
        while view.alphaValue != 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        #expect(view.alphaValue == 0)
    }

    @Test("handleHideAndSettleComplete returns state to .idle and schedules .scrollSettled")
    func hideAndSettle_completeResetsIdle() async {
        let c = makeController()
        c.effectiveScrollMode = .hideAndSettle
        c.scrollState = .faded
        // textContext is internal var per D-27 — set directly so scheduleReposition
        // has a context to operate on.
        c.textContext = makeContext(bundleID: "com.unknown.app")

        c.handleHideAndSettleComplete()

        #expect(c.scrollState == .idle)
        #expect(c.currentRepositionTask != nil)
        c.currentRepositionTask?.cancel()
        await c.currentRepositionTask?.value
    }

    // MARK: PERF-10 — frame-budget demotion (Test 5)

    @Test("3 consecutive slow frames demote trackFrame session to hideAndSettle")
    func trackFrame_demotesAfter3Slow() {
        let c = makeController()
        c.effectiveScrollMode = .trackFrame
        c.frameBudgetMisses = 0
        // Each call > 12ms budget → increments misses.
        c.recordFrameCost(elapsed: 0.020)  // miss 1
        #expect(c.effectiveScrollMode == .trackFrame)
        c.recordFrameCost(elapsed: 0.020)  // miss 2
        #expect(c.effectiveScrollMode == .trackFrame)
        c.recordFrameCost(elapsed: 0.020)  // miss 3 → demote
        #expect(c.effectiveScrollMode == .hideAndSettle)
        #expect(c.scrollState == .faded)
        #expect(c.scrollTracker == nil)
    }

    // MARK: dismiss teardown (Test 6)

    @Test("dismiss tears down tracker/timer/observer and resets scroll state")
    func dismiss_tearsDownScrollState() {
        let c = makeController()
        c.effectiveScrollMode = .trackFrame
        c.scrollState = .scrolling
        c.frameBudgetMisses = 2
        // Install a tracker without a host view: stub via a bare NSView.
        let view = NSView(frame: .zero)
        c.scrollTracker = ScrollTracker(hostView: view)
        c.hideSettleTimer = Timer.scheduledTimer(
            withTimeInterval: 10, repeats: false, block: { _ in }
        )
        c.scrollAreaObserver = ScrollAreaObserver()

        c.dismiss()

        #expect(c.scrollTracker == nil)
        #expect(c.hideSettleTimer == nil)
        #expect(c.scrollAreaObserver == nil)
        #expect(c.scrollState == .idle)
        #expect(c.frameBudgetMisses == 0)
        #expect(c.effectiveScrollMode == .hideAndSettle)
    }
}
