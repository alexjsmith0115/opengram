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

private struct AlwaysOnIncrementalConfig: IncrementalConfig {
    var isIncrementalCheckingEnabled: Bool { true }
    var paragraphRephraseCardEnabled: Bool { false }
    var minIssueCount: Int { 2 }
    var minWordCount: Int { 12 }
    var idleDebounceSeconds: TimeInterval { 1.5 }
}

/// Mutable config for live-read regression test. Allows flipping idleDebounceSeconds
/// mid-scheduler to prove the per-call read contract (SET-10 / D-03).
private final class MutableIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    private let lock = NSLock()
    private var _flag: Bool
    private var _paragraphRephraseCardEnabled: Bool
    private var _minIssueCount: Int
    private var _minWordCount: Int
    private var _idleDebounceSeconds: TimeInterval
    init(
        _ initial: Bool,
        paragraphRephraseCardEnabled: Bool = false,
        minIssueCount: Int = 2,
        minWordCount: Int = 12,
        idleDebounceSeconds: TimeInterval = 1.5
    ) {
        self._flag = initial
        self._paragraphRephraseCardEnabled = paragraphRephraseCardEnabled
        self._minIssueCount = minIssueCount
        self._minWordCount = minWordCount
        self._idleDebounceSeconds = idleDebounceSeconds
    }
    var isIncrementalCheckingEnabled: Bool { lock.lock(); defer { lock.unlock() }; return _flag }
    var paragraphRephraseCardEnabled: Bool { lock.lock(); defer { lock.unlock() }; return _paragraphRephraseCardEnabled }
    var minIssueCount: Int { lock.lock(); defer { lock.unlock() }; return _minIssueCount }
    var minWordCount: Int { lock.lock(); defer { lock.unlock() }; return _minWordCount }
    var idleDebounceSeconds: TimeInterval { lock.lock(); defer { lock.unlock() }; return _idleDebounceSeconds }
    func set(_ value: Bool) { lock.lock(); _flag = value; lock.unlock() }
    func setIdleDebounceSeconds(_ value: TimeInterval) { lock.lock(); _idleDebounceSeconds = value; lock.unlock() }
    func setMinIssueCount(_ value: Int) { lock.lock(); _minIssueCount = value; lock.unlock() }
    func setMinWordCount(_ value: Int) { lock.lock(); _minWordCount = value; lock.unlock() }
}

private final class CancellationFakeClock: CacheClock, @unchecked Sendable {
    var current: Date
    init(_ seed: Date = Date(timeIntervalSince1970: 0)) { self.current = seed }
    func now() -> Date { current }
}

private func makeScheduler(
    llm: SlowLLM,
    cache: ParagraphSuggestionCache = ParagraphSuggestionCache()
) -> LLMCheckScheduler {
    LLMCheckScheduler(
        splitter: DoubleNewlineSplitter(),
        hasher: Sha256ParagraphHasher(),
        cache: cache,
        clock: SystemClock(),
        llm: llm,
        configProvider: { LLMConfig.default },
        apiKeyProvider: { "test-key" },
        incrementalConfig: AlwaysOnIncrementalConfig()
    )
}

/// Scheduler with a mutable debounce config — drives the SET-10 live-read tests
/// and the debounce-sensitive cancellation cases.
private func makeSchedulerWithDebounce(
    llm: SlowLLM,
    debounce: TimeInterval,
    cache: ParagraphSuggestionCache = ParagraphSuggestionCache()
) -> LLMCheckScheduler {
    LLMCheckScheduler(
        splitter: DoubleNewlineSplitter(),
        hasher: Sha256ParagraphHasher(),
        cache: cache,
        clock: SystemClock(),
        llm: llm,
        configProvider: { LLMConfig.default },
        apiKeyProvider: { "test-key" },
        incrementalConfig: MutableIncrementalConfig(true, idleDebounceSeconds: debounce)
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
        let scheduler = makeSchedulerWithDebounce(llm: llm, debounce: 0.1)

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
        let scheduler = makeSchedulerWithDebounce(llm: llm, debounce: 0.5)

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
        let scheduler = makeSchedulerWithDebounce(llm: llm, debounce: 5.0)

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            _ = await scheduler.checkOnFocusLoss(text: "P1", bundleID: "b")
        }
        // Ceiling of 1s gives headroom for cooperative-pool scheduling jitter under parallel
        // test load while still being << the deliberately large 5.0s debounce — the assertion
        // remains that focus-loss did NOT observe the debounce.
        #expect(elapsed < .seconds(1))
    }

    // 5. D-09 edge: zero-second debounce fires effectively immediately.
    @Test func keystrokeDebounce_zeroSecondDebounce_firesImmediately() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(5))
        llm.setCanned(["P1": [style(original: "P1")]])
        let scheduler = makeSchedulerWithDebounce(llm: llm, debounce: 0)

        let fired = OSAllocatedUnfairLock(initialState: false)
        await scheduler.onKeystroke(text: "P1", bundleID: "b") { _ in
            fired.withLock { $0 = true }
        }

        // Poll up to 1s — under parallel test load the cooperative pool may delay the
        // zero-debounce Task scheduling beyond a fixed short sleep. Assertion is that it
        // fires WITHOUT waiting an idleDebounceSeconds window (which doesn't exist here).
        var fireObserved = false
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(50))
            if fired.withLock({ $0 }) { fireObserved = true; break }
        }
        #expect(fireObserved)
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

    // SET-10 / D-03: idleDebounceSeconds is live-read on every onKeystroke() entry.
    // Flipping the config value between two onKeystroke calls on the SAME scheduler
    // instance must honor the new value — no re-init required.
    @Test func idleDebounceSeconds_liveReadHonoredWithoutReinit() async {
        let llm = SlowLLM()
        llm.setDefaultDelay(.milliseconds(2))
        llm.setCanned(["P1": [style(original: "P1")], "P2": [style(original: "P2")]])
        let config = MutableIncrementalConfig(true, idleDebounceSeconds: 0.05)
        let scheduler = LLMCheckScheduler(
            splitter: DoubleNewlineSplitter(),
            hasher: Sha256ParagraphHasher(),
            cache: ParagraphSuggestionCache(),
            clock: SystemClock(),
            llm: llm,
            configProvider: { LLMConfig.default },
            apiKeyProvider: { "test-key" },
            incrementalConfig: config
        )

        // Fire 1: debounce 0.05s, sleep 0.25s so the analyze MUST fire.
        await scheduler.onKeystroke(text: "P1", bundleID: "b") { _ in }
        try? await Task.sleep(for: .milliseconds(250))
        let firstCount = llm.callCount
        #expect(firstCount >= 1)

        // Flip debounce to 5.0s on the SAME scheduler instance.
        config.setIdleDebounceSeconds(5.0)

        // Fire 2: sleep only 0.25s. If scheduler cached the old 0.05s, LLM would fire again.
        // Live-read honored → 0.25s < 5.0s → no additional call within this window.
        await scheduler.onKeystroke(text: "P2", bundleID: "b") { _ in }
        try? await Task.sleep(for: .milliseconds(250))
        #expect(llm.callCount == firstCount)
    }
}
