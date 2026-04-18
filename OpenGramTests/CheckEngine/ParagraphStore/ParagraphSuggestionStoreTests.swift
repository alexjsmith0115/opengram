import Testing
import Foundation
import os
@testable import OpenGramLib

@Suite struct ParagraphSuggestionStoreTests {

    // MARK: - Test doubles

    private final class StubLLM: LLMProviderProtocol, @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: State())
        private struct State {
            var calls: [String] = []
            var canned: [String: [LLMStyleSuggestion]] = [:]
        }
        var calls: [String] { state.withLock { $0.calls } }
        func setCanned(_ c: [String: [LLMStyleSuggestion]]) { state.withLock { $0.canned = c } }
        func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }
        func analyze(target: String, previousContext: String?, nextContext: String?, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] {
            // Suspension point so the cooperative thread pool can schedule other tasks.
            try? await Task.sleep(for: .milliseconds(1))
            return state.withLock { s in
                s.calls.append(target)
                return s.canned[target] ?? []
            }
        }
        func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
    }

    private final class StubCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
        var stored: [String: String] = [:]
        func isSupported(bundleID: String, version: String?) -> Bool? { nil }
        func store(bundleID: String, version: String?, supported: Bool) {}
        func isNotificationReliable(bundleID: String) -> Bool? { nil }
        func storeNotificationReliability(bundleID: String, reliable: Bool) {}
        func separator(bundleID: String, version: String?) -> String? { stored["\(bundleID):\(version ?? "nil")"] }
        func storeSeparator(bundleID: String, version: String?, separator: String) { stored["\(bundleID):\(version ?? "nil")"] = separator }
    }

    private final class FakeClock: CacheClock, @unchecked Sendable {
        var current: Date
        init(_ seed: Date = Date(timeIntervalSince1970: 1_000_000)) { self.current = seed }
        func now() -> Date { current }
    }

    private func makeStyleSuggestion(original: String, revised: String, category: LLMStyleSuggestion.Category = .clarity) -> LLMStyleSuggestion {
        LLMStyleSuggestion(
            category: category,
            originalText: original,
            revisedText: revised,
            explanation: "test",
            confidence: 1
        )
    }

    // MARK: - Factory

    /// Thread-safe text holder used by the store's `textProvider` closure. NSLock avoids
    /// the cross-actor hop hazard from the store actor calling a MainActor closure synchronously.
    private final class MainActorTextBox: @unchecked Sendable {
        private let lock = NSLock()
        private var textByBundle: [String: String] = [:]

        init(_ seed: [String: String] = [:]) { self.textByBundle = seed }

        func read(bundleID: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return textByBundle[bundleID]
        }

        func write(bundleID: String, text: String) {
            lock.lock(); defer { lock.unlock() }
            textByBundle[bundleID] = text
        }
    }

    private func makeStore(
        llm: StubLLM,
        timeout: TimeInterval = 5,
        initialTexts: [String: String] = [:]
    ) async -> (ParagraphSuggestionStore, LLMRequestQueue, MainActorTextBox) {
        let box = MainActorTextBox(initialTexts)
        let queue = LLMRequestQueue(
            llm: llm,
            configProvider: { LLMConfig(baseURL: "https://x.invalid", model: "m", enabledChecks: [], temperature: 0.2, maxTokens: 100, requestTimeout: 30, confidenceThreshold: 1) },
            apiKeyProvider: { nil },
            timeoutProvider: { timeout }
        )
        let cache = StubCapabilityCache()
        let splitter = ParagraphSplitter(capabilityCache: cache)
        let store = ParagraphSuggestionStore(
            queue: queue,
            splitter: splitter,
            clock: FakeClock(),
            textProvider: { [box] bundleID in box.read(bundleID: bundleID) },
            versionProvider: { _ in nil }
        )
        await queue.setStore(store)
        return (store, queue, box)
    }

    private func makeSet(
        bundleID: String = "b",
        _ paragraphs: [String],
        caretText: String? = nil
    ) -> ParagraphSet {
        let entries = paragraphs.map {
            ParagraphSet.Entry(hash: ParagraphHash(bundleID: bundleID, paragraphText: $0), text: $0)
        }
        let caretHash = caretText.flatMap { t in
            entries.first { $0.text == t }?.hash
        }
        return ParagraphSet(bundleID: bundleID, paragraphs: entries, caretParagraphHash: caretHash)
    }

    private func longText(_ n: Int) -> String {
        String(repeating: "a", count: n)
    }

    // MARK: - PLL-03a new paragraph submits

    @Test func reconcileNewParagraphSubmitsOnce() async throws {
        let llm = StubLLM()
        let text = longText(40) + " with words"
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": text])
        let set = makeSet(bundleID: "b", [text])
        let hash = set.paragraphs[0].hash

        await store.reconcile(set: set)
        // Wait for handleQueueResponse to complete — entry leaves .pending state
        try await waitForKind(store: store, hash: hash, notPending: true)
        #expect(llm.calls == [text])
        let kind = await store._cacheEntryKind(hash: hash)
        #expect(kind == .readyEmpty || kind == .ready)
    }

    // MARK: - PLL-03b .ready does not resubmit

    @Test func reconcileReadyEntryDoesNotResubmit() async throws {
        let llm = StubLLM()
        let text = longText(40) + " with words"
        llm.setCanned([text: [makeStyleSuggestion(original: text, revised: "rewrite")]])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": text])
        let set = makeSet(bundleID: "b", [text])
        let hash = set.paragraphs[0].hash

        await store.reconcile(set: set)
        // Wait for handleQueueResponse to finish — cache transitions from .pending to .ready
        try await waitForKind(store: store, hash: hash, equals: .ready)

        await store.reconcile(set: set)
        try await Task.sleep(for: .milliseconds(50))
        #expect(llm.calls.count == 1, "ready entry should not re-submit")
    }

    // MARK: - PLL-03c .pending does not resubmit

    @Test func reconcilePendingEntryDoesNotResubmit() async throws {
        let llm = StubLLM()
        let text = longText(40) + " with words"
        llm.setCanned([text: []])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": text])
        let set = makeSet(bundleID: "b", [text])

        await store.reconcile(set: set)
        // Don't wait for completion; re-reconcile while still pending
        await store.reconcile(set: set)
        try await Task.sleep(for: .milliseconds(50))
        try await wait(until: { llm.calls.count >= 1 })
        #expect(llm.calls.count == 1, "pending entry should not re-submit")
    }

    // MARK: - PLL-04 invalidate does not submit

    @Test func invalidateDisplayedDoesNotSubmit() async throws {
        let llm = StubLLM()
        let text = longText(40) + " with words"
        let (store, _, _) = await makeStore(llm: llm)
        let set = makeSet(bundleID: "b", [text])

        await store.invalidateDisplayed(bundleID: "b", currentSet: set)
        try await Task.sleep(for: .milliseconds(50))
        #expect(llm.calls.isEmpty)
        let count = await store._cacheCount()
        #expect(count == 0)
    }

    // MARK: - PLL-05 response for hash not in set → drop + evict

    @Test func handleResponseHashNotInSetDropsAndEvicts() async throws {
        let llm = StubLLM()
        let original = longText(40) + " original"
        let replacement = longText(40) + " different"
        llm.setCanned([original: [makeStyleSuggestion(original: original, revised: "r")]])
        let (store, queue, box) = await makeStore(llm: llm, initialTexts: ["b": original])
        _ = queue
        let set = makeSet(bundleID: "b", [original])

        await store.reconcile(set: set)
        // Swap the text under the store BEFORE the response comes in to exercise
        // the drop-on-stale verify path.
        box.write(bundleID: "b", text: replacement)
        let goneHash = set.paragraphs[0].hash
        await store.handleQueueResponse(
            hash: goneHash,
            bundleID: "b",
            result: .success([makeStyleSuggestion(original: original, revised: "r")])
        )
        let kind = await store._cacheEntryKind(hash: goneHash)
        #expect(kind == nil, "entry should be evicted when hash not in live set")
    }

    // MARK: - PLL-06 caret paragraph skipped

    @Test func reconcileCaretParagraphSkipped() async throws {
        let llm = StubLLM()
        let a = longText(40) + " a"
        let b = longText(40) + " b"
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": a + "\n\n" + b])
        let set = makeSet(bundleID: "b", [a, b], caretText: a)
        let bHash = set.paragraphs[1].hash

        await store.reconcile(set: set)
        // Wait for b (the non-caret paragraph) to be processed
        try await waitForKind(store: store, hash: bHash, notEqual: .pending)
        #expect(llm.calls == [b], "caret paragraph must not be submitted")
    }

    // MARK: - PLL-07 paragraph leaves while pending — cancel + evict

    @Test func reconcileParagraphLeavesWhilePendingCancelsAndEvicts() async throws {
        let llm = StubLLM()
        let a = longText(40) + " a"
        let b = longText(40) + " b"
        llm.setCanned([a: [], b: []])

        // Slow queue so we have a pending window
        let (store, _, _) = await makeStore(llm: llm, timeout: 5, initialTexts: ["b": a])
        let setA = makeSet(bundleID: "b", [a])
        await store.reconcile(set: setA)
        let pendingHash = setA.paragraphs[0].hash
        let kindPending = await store._cacheEntryKind(hash: pendingHash)
        #expect(kindPending == .pending || kindPending == .readyEmpty)

        // Now reconcile with a DIFFERENT paragraph set (a gone, only b present)
        let setB = makeSet(bundleID: "b", [b])
        await store.reconcile(set: setB)

        let evicted = await store._cacheEntryKind(hash: pendingHash)
        #expect(evicted == nil, "paragraph A's entry must be evicted on sweep")
    }

    // MARK: - PLL-08a/b per-bundle isolation

    @Test func reconcilePerBundleIsolation() async throws {
        let llm = StubLLM()
        let t = longText(40) + " text"
        llm.setCanned([t: []])

        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["app.a": t, "app.b": t])
        let setA = makeSet(bundleID: "app.a", [t])
        let setB = makeSet(bundleID: "app.b", [t])

        await store.reconcile(set: setA)
        try await Task.sleep(for: .milliseconds(30))
        await store.reconcile(set: setB)
        try await Task.sleep(for: .milliseconds(30))

        // Now reconcile app.a with empty set — app.a entry evicts, app.b entry remains.
        let emptyA = ParagraphSet(bundleID: "app.a", paragraphs: [], caretParagraphHash: nil)
        await store.reconcile(set: emptyA)

        let cA = await store._cacheCount(bundleID: "app.a")
        let cB = await store._cacheCount(bundleID: "app.b")
        #expect(cA == 0, "app.a swept")
        #expect(cB == 1, "app.b untouched (PLL-08b)")
    }

    // MARK: - PLL-14 readyEmpty prevents re-fire

    @Test func readyEmptyPreventsResubmit() async throws {
        let llm = StubLLM()
        let t = longText(40) + " text"
        llm.setCanned([t: []])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": t])
        let set = makeSet(bundleID: "b", [t])
        let hash = set.paragraphs[0].hash

        await store.reconcile(set: set)
        // Wait for handleQueueResponse to finish — cache transitions from .pending to .readyEmpty
        try await waitForKind(store: store, hash: hash, equals: .readyEmpty)

        await store.reconcile(set: set)
        try await Task.sleep(for: .milliseconds(40))
        #expect(llm.calls.count == 1, "readyEmpty should not re-fire")
    }

    // MARK: - markDismissed / markAccepted

    @Test func markDismissedTransitionsToDismissed() async throws {
        let llm = StubLLM()
        let t = longText(40) + " text"
        llm.setCanned([t: []])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": t])
        let set = makeSet(bundleID: "b", [t])
        let h = set.paragraphs[0].hash

        await store.reconcile(set: set)
        try await waitForKind(store: store, hash: h, equals: .readyEmpty)

        await store.markDismissed(hash: h)
        let kind = await store._cacheEntryKind(hash: h)
        #expect(kind == .dismissed)

        await store.reconcile(set: set)
        try await Task.sleep(for: .milliseconds(40))
        #expect(llm.calls.count == 1, ".dismissed should not re-fire")
    }

    @Test func markAcceptedTransitionsToAccepted() async throws {
        let llm = StubLLM()
        let t = longText(40) + " text"
        llm.setCanned([t: []])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": t])
        let set = makeSet(bundleID: "b", [t])
        let h = set.paragraphs[0].hash

        await store.reconcile(set: set)
        try await waitForKind(store: store, hash: h, equals: .readyEmpty)

        await store.markAccepted(hash: h)
        let kind = await store._cacheEntryKind(hash: h)
        #expect(kind == .accepted)
    }

    // MARK: - Render surface

    @Test func renderableSuggestionsFilterByLiveSetAndReadyState() async throws {
        let llm = StubLLM()
        let t = longText(40) + " text"
        llm.setCanned([t: [makeStyleSuggestion(original: t, revised: "rewrite")]])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": t])
        let set = makeSet(bundleID: "b", [t])
        let hash = set.paragraphs[0].hash

        await store.reconcile(set: set)
        // Wait for handleQueueResponse to complete — cache must be .ready
        try await waitForKind(store: store, hash: hash, equals: .ready)
        let sugs = await store.renderableSuggestions(for: "b")
        #expect(sugs.count == 1)
        #expect(sugs[0].source == .llm)
        #expect(sugs[0].primaryReplacement == "rewrite")
    }

    // MARK: - Min length guard

    @Test func reconcileSkipsShortParagraphs() async throws {
        let llm = StubLLM()
        let short = "short" // 5 chars — below default 30
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": short])
        let set = makeSet(bundleID: "b", [short])
        await store.reconcile(set: set)
        try await Task.sleep(for: .milliseconds(30))
        #expect(llm.calls.isEmpty)
        let count = await store._cacheCount()
        #expect(count == 0)
    }

    // MARK: - Events

    @Test func reconcileEmitsEvent() async throws {
        let llm = StubLLM()
        let t = longText(40) + " text"
        llm.setCanned([t: []])
        let (store, _, _) = await makeStore(llm: llm, initialTexts: ["b": t])

        var iter = store.events.makeAsyncIterator()
        let set = makeSet(bundleID: "b", [t])
        await store.reconcile(set: set)
        let ev = await iter.next()
        guard case .suggestionsChanged(let bundleID) = ev else {
            Issue.record("expected event")
            return
        }
        #expect(bundleID == "b")
    }

    // MARK: - Helpers

    /// Polls the store's cache entry kind until it equals `kind` or times out.
    /// Directly observes the store actor state — avoids the LLM-call-count race
    /// where `llm.calls.count == 1` but `handleQueueResponse` hasn't completed
    /// yet (two async hops: queue actor → store actor → cache write).
    private func waitForKind(
        store: ParagraphSuggestionStore,
        hash: ParagraphHash,
        equals target: ParagraphSuggestionState.Kind,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let kind = await store._cacheEntryKind(hash: hash)
            if kind == target { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let final = await store._cacheEntryKind(hash: hash)
        Issue.record("timed out waiting for \(target); got \(String(describing: final))")
    }

    /// Polls until the cache entry kind is NOT `notEqual` (e.g., waits for entry to appear).
    private func waitForKind(
        store: ParagraphSuggestionStore,
        hash: ParagraphHash,
        notEqual excluded: ParagraphSuggestionState.Kind?,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let kind = await store._cacheEntryKind(hash: hash)
            if kind != excluded { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let final = await store._cacheEntryKind(hash: hash)
        Issue.record("timed out; still got \(String(describing: final))")
    }

    /// Polls until the cache entry is past `.pending` (i.e., handleQueueResponse completed).
    private func waitForKind(
        store: ParagraphSuggestionStore,
        hash: ParagraphHash,
        notPending: Bool,
        timeout: Duration = .seconds(10)
    ) async throws {
        guard notPending else { return }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            let kind = await store._cacheEntryKind(hash: hash)
            if kind != nil && kind != .pending { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        let final = await store._cacheEntryKind(hash: hash)
        Issue.record("timed out waiting past .pending; got \(String(describing: final))")
    }

    private func wait(until p: @Sendable @escaping () -> Bool, timeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if p() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out")
    }
}
