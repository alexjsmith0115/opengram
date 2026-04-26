import Testing
import Foundation
import os
@testable import OpenGramLib

@Suite struct LLMRequestQueueTests {

    // MARK: - Test doubles

    private final class StubLLM: LLMProviderProtocol, @unchecked Sendable {
        struct Call: Sendable {
            let target: String
        }
        private let state = OSAllocatedUnfairLock(initialState: State())
        private struct State {
            var calls: [Call] = []
            var delay: Duration = .zero
            var canned: [String: [LLMStyleSuggestion]] = [:]
            var cancelledTargets: [String] = []
        }
        var calls: [Call] { state.withLock { $0.calls } }
        var cancelledTargets: [String] { state.withLock { $0.cancelledTargets } }
        func setDelay(_ d: Duration) { state.withLock { $0.delay = d } }
        func setCanned(_ c: [String: [LLMStyleSuggestion]]) { state.withLock { $0.canned = c } }

        func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String]) async -> [LLMStyleSuggestion] { [] }

        func analyze(
            target: String,
            previousContext: String?,
            nextContext: String?,
            config: LLMConfig,
            apiKey: String?,
            harperSpans: [String]
        ) async -> [LLMStyleSuggestion] {
            let delay: Duration = state.withLock { s in
                s.calls.append(Call(target: target))
                return s.delay
            }
            do { try await Task.sleep(for: delay) }
            catch {
                state.withLock { $0.cancelledTargets.append(target) }
                return []
            }
            if Task.isCancelled {
                state.withLock { $0.cancelledTargets.append(target) }
                return []
            }
            return state.withLock { $0.canned[target] ?? [] }
        }

        func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool { true }
    }

    private final class RecordingStore: LLMRequestQueueStore, @unchecked Sendable {
        struct Delivery: Sendable {
            let hash: ParagraphHash
            let bundleID: String
            let kind: Kind
            enum Kind: Sendable { case success(Int); case failure(String) }
        }
        private let state = OSAllocatedUnfairLock(initialState: [Delivery]())
        var deliveries: [Delivery] { state.withLock { $0 } }

        func handleQueueResponse(
            hash: ParagraphHash,
            bundleID: String,
            result: Result<[LLMStyleSuggestion], Error>
        ) async {
            let kind: Delivery.Kind
            switch result {
            case .success(let s): kind = .success(s.count)
            case .failure(let e): kind = .failure("\(type(of: e))")
            }
            state.withLock { $0.append(Delivery(hash: hash, bundleID: bundleID, kind: kind)) }
        }
    }

    // MARK: - Factory

    private func makeQueue(
        llm: StubLLM,
        timeout: TimeInterval = 5
    ) -> (LLMRequestQueue, RecordingStore) {
        let queue = LLMRequestQueue(
            llm: llm,
            configProvider: { .default },
            apiKeyProvider: { nil },
            timeoutProvider: { timeout }
        )
        let store = RecordingStore()
        Task { await queue.setStore(store) }
        return (queue, store)
    }

    private func hash(_ text: String, bundle: String = "b") -> ParagraphHash {
        ParagraphHash(bundleID: bundle, paragraphText: text)
    }

    // MARK: - PLL-10a: FIFO

    @Test func submitPreservesFIFO() async throws {
        let llm = StubLLM()
        llm.setCanned(["P1": [], "P2": [], "P3": []])
        let (q, store) = makeQueue(llm: llm)
        await q.setStore(store)

        let h1 = hash("P1"), h2 = hash("P2"), h3 = hash("P3")
        await q.submit(hash: h1, paragraph: "P1", bundleID: "b")
        await q.submit(hash: h2, paragraph: "P2", bundleID: "b")
        await q.submit(hash: h3, paragraph: "P3", bundleID: "b")

        try await wait(until: { store.deliveries.count == 3 })
        #expect(store.deliveries.map(\.hash) == [h1, h2, h3])
    }

    // MARK: - PLL-10b: one in flight

    @Test func oneInFlightAtATime() async throws {
        let llm = StubLLM()
        llm.setDelay(.milliseconds(80))
        llm.setCanned(["P1": [], "P2": []])
        let (q, store) = makeQueue(llm: llm)
        await q.setStore(store)

        await q.submit(hash: hash("P1"), paragraph: "P1", bundleID: "b")
        await q.submit(hash: hash("P2"), paragraph: "P2", bundleID: "b")

        try await Task.sleep(for: .milliseconds(20))
        #expect(llm.calls.count == 1, "only P1 should be in-flight; P2 waiting")

        try await wait(until: { store.deliveries.count == 2 })
        #expect(llm.calls.map(\.target) == ["P1", "P2"])
    }

    // MARK: - PLL-10c: cancel queued (not fired)

    @Test func cancelQueuedDoesNotFire() async throws {
        let llm = StubLLM()
        llm.setDelay(.milliseconds(80))
        llm.setCanned(["P1": [], "P2": [], "P3": []])
        let (q, store) = makeQueue(llm: llm)
        await q.setStore(store)

        await q.submit(hash: hash("P1"), paragraph: "P1", bundleID: "b")
        await q.submit(hash: hash("P2"), paragraph: "P2", bundleID: "b")
        await q.submit(hash: hash("P3"), paragraph: "P3", bundleID: "b")

        try await Task.sleep(for: .milliseconds(10))
        await q.cancel(hash: hash("P2"))

        try await wait(until: { store.deliveries.count == 2 })
        #expect(llm.calls.map(\.target) == ["P1", "P3"])
        #expect(store.deliveries.map(\.hash) == [hash("P1"), hash("P3")])
    }

    // MARK: - PLL-10d: cancel in-flight propagates + no store notification

    @Test func cancelInFlightPropagatesAndSilentToStore() async throws {
        let llm = StubLLM()
        llm.setDelay(.seconds(3))
        let (q, store) = makeQueue(llm: llm, timeout: 10)
        await q.setStore(store)

        await q.submit(hash: hash("P1"), paragraph: "P1", bundleID: "b")
        try await Task.sleep(for: .milliseconds(50))
        await q.cancel(hash: hash("P1"))

        // Give the cancel + next-pump cycle time to settle
        try await Task.sleep(for: .milliseconds(200))

        #expect(llm.cancelledTargets.contains("P1"))
        #expect(store.deliveries.isEmpty, "cancel should NOT notify store")
        let depth = await q.queueDepth
        let inFlight = await q.isInFlight
        #expect(depth == 0)
        #expect(inFlight == false)
    }

    // MARK: - PLL-10e: timeout → .failure

    @Test func timeoutProducesFailed() async throws {
        let llm = StubLLM()
        llm.setDelay(.seconds(2))
        let (q, store) = makeQueue(llm: llm, timeout: 0.1)
        await q.setStore(store)

        await q.submit(hash: hash("P1"), paragraph: "P1", bundleID: "b")
        try await wait(until: { !store.deliveries.isEmpty })

        #expect(store.deliveries.count == 1)
        if case .failure(let typeName) = store.deliveries[0].kind {
            #expect(typeName == "TimeoutError")
        } else {
            Issue.record("expected .failure, got \(store.deliveries[0].kind)")
        }
    }

    @Test func filtersProviderResultsBelowConfigThreshold() async throws {
        let llm = StubLLM()
        llm.setCanned([
            "P1": [
                LLMStyleSuggestion(category: .tone, originalText: "P1", revisedText: "low", explanation: "", confidence: 8),
                LLMStyleSuggestion(category: .rephrase, originalText: "P1", revisedText: "high", explanation: "", confidence: 9)
            ]
        ])
        let (q, store) = makeQueue(llm: llm)
        await q.setStore(store)

        await q.submit(hash: hash("P1"), paragraph: "P1", bundleID: "b")
        try await wait(until: { !store.deliveries.isEmpty })

        #expect(store.deliveries.count == 1)
        if case .success(let count) = store.deliveries[0].kind {
            #expect(count == 1)
        } else {
            Issue.record("expected .success, got \(store.deliveries[0].kind)")
        }
    }

    @Test func cancelUnknownHashIsNoOp() async {
        let llm = StubLLM()
        let (q, _) = makeQueue(llm: llm)
        await q.cancel(hash: hash("ghost"))
        let depth = await q.queueDepth
        #expect(depth == 0)
    }

    // MARK: - Helpers

    private func wait(
        until predicate: @Sendable @escaping () -> Bool,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for predicate")
    }
}
