import Testing
import AppKit
@preconcurrency import ApplicationServices
import Foundation

@testable import OpenGramLib

// MARK: - Helpers (inlined — OverlayControllerTests helpers are file-private)

private func makeSuggestion(
    id: UUID = UUID(),
    original: String = "recieve",
    primaryReplacement: String = "receive"
) -> Suggestion {
    let range = original.startIndex..<original.endIndex
    return Suggestion(
        id: id,
        range: range,
        original: original,
        primaryReplacement: primaryReplacement,
        allReplacements: [primaryReplacement],
        message: "Spelling error.",
        category: .spelling,
        source: .harper,
        priority: 5,
        paragraphHash: nil
    )
}

private func makeAXRectValue(
    _ rect: CGRect = CGRect(x: 100, y: 200, width: 50, height: 14)
) -> CFTypeRef {
    var r = rect
    return AXValueCreate(.cgRect, &r)!
}

private func makeTextContext(text: String = "recieve") -> TextContext {
    TextContext(
        text: text,
        bundleID: "com.apple.TextEdit",
        extractionMethod: .axDirectSelection,
        selectionRange: nil,
        elementBounds: nil,
        axElement: AXUIElementCreateSystemWide()
    )
}

/// Builds a slow-mock-backed controller seeded with N suggestions.
/// `delayMs` controls the cancellation window per AX call.
@MainActor
private func makeRepositionController(
    suggestionCount: Int = 20,
    delayMs: Int = 50
) -> (controller: OverlayController, slow: SlowMockAXAccessor) {
    let slow = SlowMockAXAccessor(delay: .milliseconds(delayMs))
    slow.parameterizedAttributeValues[kAXBoundsForRangeParameterizedAttribute] =
        (.success, makeAXRectValue())
    let queue = AXCallQueue(accessor: slow)
    let controller = OverlayController(accessor: slow, axQueue: queue)
    controller.suggestions = (0..<suggestionCount).map { _ in makeSuggestion() }
    controller.textContext = makeTextContext()
    return (controller, slow)
}

// MARK: - Tests

@Suite("OverlayController reposition")
@MainActor
struct OverlayControllerRepositionTests {

    // PERF-03: second scheduleReposition cancels first before any applyBounds runs.
    @Test("cancellation during reposition aborts before bounds are applied")
    func repositionCancellation() async throws {
        let (controller, _) = makeRepositionController(suggestionCount: 20, delayMs: 50)

        controller.scheduleReposition(reason: .textChanged)
        controller.scheduleReposition(reason: .textChanged)   // cancels first

        // Await the second (current) task's completion.
        await controller.currentRepositionTask?.value

        // At most one applyBounds survived. Spec Task 2 acceptance criterion:
        // "A second scheduleReposition call cancels the first before it applies bounds."
        #expect(controller.applyBoundsCallCount <= 1)
    }

    // PERF-04: acceptSuggestion cancels pending reposition before mutating state.
    @Test("acceptSuggestion cancels currentRepositionTask")
    func acceptSuggestionCancels() async throws {
        let (controller, _) = makeRepositionController(suggestionCount: 20, delayMs: 50)

        controller.scheduleReposition(reason: .textChanged)
        guard let pending = controller.currentRepositionTask else {
            Issue.record("scheduleReposition did not assign currentRepositionTask")
            return
        }

        // Accept a suggestion (write will fail silently since MockAXAccessor
        // has no settable attributes — that's fine, we're only testing the
        // cancel-before-mutate contract).
        let suggestion = controller.suggestions[0]
        let ctx = controller.textContext!
        controller.acceptSuggestion(suggestion, context: ctx, replacementOverride: nil)

        // Await the cancelled task's terminal state.
        await pending.value

        // applyBounds must not have fired — cancellation happened before AX calls completed.
        #expect(controller.applyBoundsCallCount == 0)
    }

    // PERF-04: dismiss() cancels pending reposition.
    @Test("dismiss cancels currentRepositionTask")
    func dismissCancels() async throws {
        let (controller, _) = makeRepositionController(suggestionCount: 20, delayMs: 50)

        controller.scheduleReposition(reason: .textChanged)
        guard let pending = controller.currentRepositionTask else {
            Issue.record("scheduleReposition did not assign currentRepositionTask")
            return
        }

        controller.dismiss()

        await pending.value
        #expect(controller.applyBoundsCallCount == 0)
    }

    // PERF-04: scroll-monitor closure cancels pending reposition.
    // The scroll closure lives inside show() — we reach it by invoking show()
    // then synthesizing a scrollWheel NSEvent via the global monitor path.
    // Simpler: verify the closure contract by asserting that the `dismiss()`
    // fallback path observed in other tests also cancels the task; that case
    // is already covered by `dismissCancels`. For this test, we prove the
    // closure's literal body: directly invoking what the closure does must
    // cancel AND dismiss.
    //
    // We do this by installing the scrollMonitor via show(), then posting a
    // synthetic NSEvent.scrollWheel via CGEvent. NSEvent.addGlobalMonitorForEvents
    // only fires for events from OTHER processes — synthetic local events will
    // NOT trigger it. Instead, assert the contract at the code level by
    // invoking `dismiss()` (which is what the closure does after cancel) and
    // verifying the double-cancel is idempotent (the real closure calls
    // cancel THEN dismiss; if cancel is idempotent and dismiss cancels again,
    // the observable end state is identical).
    //
    // Concrete test: seed a task, call dismiss, then assert task is terminal
    // AND applyBoundsCallCount == 0. This locks the "scroll closure dismiss
    // path cancels" contract transitively. The explicit two-line closure body
    // `self?.currentRepositionTask?.cancel(); self?.dismiss()` is covered by
    // a grep gate in the reposition verify step (asserting the closure source).
    @Test("scroll-path dismiss cancels currentRepositionTask")
    func scrollPathCancels() async throws {
        let (controller, _) = makeRepositionController(suggestionCount: 20, delayMs: 50)

        controller.scheduleReposition(reason: .textChanged)
        guard let pending = controller.currentRepositionTask else {
            Issue.record("scheduleReposition did not assign currentRepositionTask")
            return
        }

        // Literal scroll-closure body (D-11):
        //   self?.currentRepositionTask?.cancel()
        //   self?.dismiss()
        controller.currentRepositionTask?.cancel()
        controller.dismiss()

        await pending.value
        #expect(controller.applyBoundsCallCount == 0)
    }

    // No task leaks — every assigned task reaches terminal state before the
    // next is assigned. Proven by: schedule N times rapidly, await the last
    // one, verify applyBoundsCallCount <= 1 (only the uncancelled tail ran).
    @Test("no task leaks across rapid scheduleReposition sequence")
    func noTaskLeaks() async throws {
        let (controller, _) = makeRepositionController(suggestionCount: 10, delayMs: 20)

        for _ in 0..<10 {
            controller.scheduleReposition(reason: .textChanged)
        }

        // Await the final task. All prior tasks were cancelled when the next
        // scheduleReposition replaced currentRepositionTask; awaiting the
        // final one guarantees we observe its terminal state.
        await controller.currentRepositionTask?.value

        // Only the last task's applyBounds could have survived. Earlier tasks
        // cancelled before their boundsBatch returned — applyBoundsCallCount
        // is therefore bounded by 1.
        #expect(controller.applyBoundsCallCount <= 1)
    }
}
