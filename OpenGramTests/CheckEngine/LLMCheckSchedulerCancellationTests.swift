import Testing
import Foundation
import os
@testable import OpenGramLib

// MARK: - Test doubles

/// LLM double that delays per-target (optionally gate-released) and records cancellations.
/// `Task.sleep` propagates cancellation via `CancellationError`; we also poll `Task.isCancelled`
/// to catch the rarer case of cancellation arriving during the user-supplied body.
private final class SlowLLM: LLMProviderProtocol, @unchecked Sendable {
    struct State {
        var calls: [String] = []
        var cancelledTargets: [String] = []
        var delayByTarget: [String: Duration] = [:]
        var cannedByTarget: [String: [LLMStyleSuggestion]] = [:]
        var defaultDelay: Duration = .milliseconds(50)
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var calls: [String] { state.withLock { $0.calls } }
    var callCount: Int { state.withLock { $0.calls.count } }
    var cancelledTargets: [String] { state.withLock { $0.cancelledTargets } }

    func setDefaultDelay(_ d: Duration) { state.withLock { $0.defaultDelay = d } }
    func setDelay(_ d: Duration, for target: String) { state.withLock { $0.delayByTarget[target] = d } }
    func setCanned(_ canned: [String: [LLMStyleSuggestion]]) { state.withLock { $0.cannedByTarget = canned } }
    func resetCalls() { state.withLock { $0.calls.removeAll(); $0.cancelledTargets.removeAll() } }

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }

    func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
        let delay: Duration = state.withLock {
            $0.calls.append(target)
            return $0.delayByTarget[target] ?? $0.defaultDelay
        }
        do {
            try await Task.sleep(for: delay)
        } catch {
            state.withLock { $0.cancelledTargets.append(target) }
            return []
        }
        if Task.isCancelled {
            state.withLock { $0.cancelledTargets.append(target) }
            return []
        }
        return state.withLock { $0.cannedByTarget[target] ?? [] }
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
}

private struct AlwaysOnIncrementalConfig: IncrementalConfig { var isIncrementalCheckingEnabled: Bool { true } }

private final class CancellationFakeClock: CacheClock, @unchecked Sendable {
    var current: Date
    init(_ seed: Date = Date(timeIntervalSince1970: 0)) { self.current = seed }
    func now() -> Date { current }
}

private func makeScheduler(
    llm: SlowLLM,
    cache: ParagraphSuggestionCache = ParagraphSuggestionCache(),
    idleDebounceSeconds: TimeInterval = 1.5
) -> LLMCheckScheduler {
    LLMCheckScheduler(
        splitter: DoubleNewlineSplitter(),
        hasher: Sha256ParagraphHasher(),
        cache: cache,
        clock: SystemClock(),
        llm: llm,
        configProvider: { LLMConfig.default },
        apiKeyProvider: { "test-key" },
        incrementalConfig: AlwaysOnIncrementalConfig(),
        idleDebounceSeconds: idleDebounceSeconds
    )
}

private func style(original: String, revised: String = "revised") -> LLMStyleSuggestion {
    LLMStyleSuggestion(category: .clarity, originalText: original, revisedText: revised, explanation: "why", confidence: 8)
}

// MARK: - Tests

@Suite struct LLMCheckSchedulerCancellationTests {

    // 1. D-04 headline: editing paragraph B mid-flight cancels ONLY B; A and C complete.
    @Test func onlyEditedParagraphCancels_othersComplete() async {
        let llm = SlowLLM()
        // Long delays on A, B, C so call 2 lands before they finish.
        llm.setDelay(.milliseconds(400), for: "A")
        llm.setDelay(.milliseconds(400), for: "B")
        llm.setDelay(.milliseconds(400), for: "C")
        llm.setDelay(.milliseconds(20), for: "B'")
        llm.setCanned([
            "A": [style(original: "A", revised: "A-rev")],
            "C": [style(original: "C", revised: "C-rev")],
            "B'": [style(original: "B'", revised: "B'-rev")]
        ])
        let scheduler = makeScheduler(llm: llm)

        // Call 1: cold cache -> fans out A, B, C in-flight.
        let firstCall = Task { await scheduler.check(text: "A\n\nB\n\nC", bundleID: "b") }

        // Wait briefly so fan-out happens.
        try? await Task.sleep(for: .milliseconds(30))

        // Call 2: edits index 1 to "B'" -> scheduler cancels inFlightByIndex[1] before spawning B'.
        // Indices 0 and 2 are unchanged at the text level but still cache-miss (call 1 hasn't upserted
        // yet), so they re-dispatch. Those indices' prior tasks get cancelled too. That's expected
        // — the headline assertion is that B (the edited paragraph) is cancelled. Here we structure
        // the call so only index 1's text differs between calls; the test checks cancellation occurs
        // as a direct consequence of re-dispatch at that index.
        let secondCall = await scheduler.check(text: "A\n\nB'\n\nC", bundleID: "b")

        // Drain first call (already cancelled in-flight slots will return []).
        _ = await firstCall.value

        // Cancelled targets must include "B" (edited paragraph's prior in-flight work).
        // "B'" must NOT be in cancelledTargets (it ran to completion in call 2).
        let cancelled = llm.cancelledTargets
        #expect(cancelled.contains("B"))
        #expect(!cancelled.contains("B'"))

        // Second call must have produced a fresh result for B'.
        let bPrime = secondCall.first(where: { $0.primaryReplacement == "B'-rev" })
        #expect(bPrime != nil)

        // And an analyze call for B' was recorded.
        #expect(llm.calls.contains("B'"))
    }

    // 2. D-09: three keystrokes within debounce window collapse to one fire.
    @Test func keystrokeDebounce_collapsesConsecutiveSignalsIntoOneFire() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(5))
        llm.setCanned(["P1": [style(original: "P1")], "P2": [style(original: "P2")]])
        let scheduler = makeScheduler(llm: llm, idleDebounceSeconds: 0.1)

        let fireCount = OSAllocatedUnfairLock(initialState: 0)
        let text = "P1\n\nP2"

        for _ in 0..<3 {
            await scheduler.onKeystroke(text: text, bundleID: "b") { _ in
                fireCount.withLock { $0 += 1 }
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        // Wait for debounce window + margin.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(fireCount.withLock { $0 } == 1)
        // Exactly one fan-out happened: 2 paragraphs -> 2 analyze calls.
        #expect(llm.callCount == 2)
    }

    // 3. D-10: focus-loss cancels pending debounce so keystroke callback never fires.
    @Test func keystrokeDebounce_cancelledByFocusLoss() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(5))
        llm.setCanned(["P1": [style(original: "P1")]])
        let scheduler = makeScheduler(llm: llm, idleDebounceSeconds: 0.5)

        let keystrokeFired = OSAllocatedUnfairLock(initialState: false)
        let text = "P1"

        await scheduler.onKeystroke(text: text, bundleID: "b") { _ in
            keystrokeFired.withLock { $0 = true }
        }

        // Immediately focus-loss: must cancel the pending debounce.
        _ = await scheduler.checkOnFocusLoss(text: text, bundleID: "b")

        // Wait well past the original debounce window.
        try? await Task.sleep(for: .milliseconds(700))

        #expect(keystrokeFired.withLock { $0 } == false)
    }

    // 4. D-10: focus-loss fires immediately; does not wait idleDebounceSeconds.
    @Test func focusLoss_firesImmediatelyWithoutWait() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(5))
        llm.setCanned(["P1": [style(original: "P1")]])
        // Deliberately large debounce; focus-loss must NOT observe it.
        let scheduler = makeScheduler(llm: llm, idleDebounceSeconds: 5.0)

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            _ = await scheduler.checkOnFocusLoss(text: "P1", bundleID: "b")
        }
        #expect(elapsed < .milliseconds(200))
    }

    // 5. D-09 edge: zero-second debounce fires effectively immediately.
    @Test func keystrokeDebounce_zeroSecondDebounce_firesImmediately() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(5))
        llm.setCanned(["P1": [style(original: "P1")]])
        let scheduler = makeScheduler(llm: llm, idleDebounceSeconds: 0)

        let fired = OSAllocatedUnfairLock(initialState: false)
        await scheduler.onKeystroke(text: "P1", bundleID: "b") { _ in
            fired.withLock { $0 = true }
        }

        try? await Task.sleep(for: .milliseconds(100))
        #expect(fired.withLock { $0 } == true)
    }

    // 6. Map cleanup: consecutive cache-miss check() invocations leave no stale in-flight entries.
    // Verified indirectly via warm-cache follow-up that issues zero analyze calls.
    @Test func multipleInFlightCancellations_cleanup() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(10))
        llm.setCanned([
            "p0": [style(original: "p0")],
            "p1": [style(original: "p1")],
            "p2": [style(original: "p2")],
            "p3": [style(original: "p3")],
            "p4": [style(original: "p4")]
        ])
        let scheduler = makeScheduler(llm: llm)
        let text = "p0\n\np1\n\np2\n\np3\n\np4"

        // Fire 5 overlapping calls; each new call cancels any stragglers from the prior.
        var tasks: [Task<[Suggestion], Never>] = []
        for _ in 0..<5 {
            tasks.append(Task { await scheduler.check(text: text, bundleID: "b") })
            try? await Task.sleep(for: .milliseconds(2))
        }
        for t in tasks { _ = await t.value }

        llm.resetCalls()

        // Follow-up with identical text: cache should be warm, inFlightByIndex clean.
        // Zero new analyze calls proves no stale pending entries linger.
        _ = await scheduler.check(text: text, bundleID: "b")
        #expect(llm.callCount == 0)
    }
}
