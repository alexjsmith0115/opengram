import Foundation

/// Serializes paragraph LLM requests. Strict FIFO, one-in-flight, per-request timeout.
///
/// Lifecycle:
/// 1. Construct with `llm`, `configProvider`, `apiKeyProvider`, `timeoutProvider`.
/// 2. Call `setStore(_:)` before any `submit(…)` (AppDelegate composition).
/// 3. `submit(…)` appends to FIFO and pumps if idle.
/// 4. `cancel(hash:)` removes still-queued or cancels in-flight; store is NOT notified.
///
/// Thread safety: all state mutations serialized by the actor. `llm.analyze` is called
/// without the actor lock via `Task { … }` so the analyze hop does not block the queue.
actor LLMRequestQueue {
    private struct QueueEntry: Sendable {
        let hash: ParagraphHash
        let paragraph: String
        let bundleID: String
    }

    private struct InFlight {
        let hash: ParagraphHash
        let bundleID: String
        let task: Task<Void, Never>
    }

    private var queued: [QueueEntry] = []
    private var inFlight: InFlight?
    /// `true` once a cancel arrives for the current in-flight hash — suppresses the
    /// response callback that fires at Task completion.
    private var inFlightCancelled = false

    private let llm: any LLMProviderProtocol
    private let configProvider: @Sendable () -> LLMConfig
    private let apiKeyProvider: @Sendable () -> String?
    private let timeoutProvider: @Sendable () -> TimeInterval
    private weak var store: (any LLMRequestQueueStore)?

    init(
        llm: any LLMProviderProtocol,
        configProvider: @Sendable @escaping () -> LLMConfig,
        apiKeyProvider: @Sendable @escaping () -> String?,
        timeoutProvider: @Sendable @escaping () -> TimeInterval
    ) {
        self.llm = llm
        self.configProvider = configProvider
        self.apiKeyProvider = apiKeyProvider
        self.timeoutProvider = timeoutProvider
    }

    func setStore(_ store: any LLMRequestQueueStore) {
        self.store = store
    }

    // MARK: - Public API

    func submit(hash: ParagraphHash, paragraph: String, bundleID: String) {
        queued.append(QueueEntry(hash: hash, paragraph: paragraph, bundleID: bundleID))
        pump()
    }

    func cancel(hash: ParagraphHash) {
        queued.removeAll { $0.hash == hash }
        if inFlight?.hash == hash {
            inFlightCancelled = true
            inFlight?.task.cancel()
            // Do NOT clear inFlight here — the Task's completion handler clears it
            // and then calls pump(). Clearing here would race pump() with the next submit.
        }
    }

    // MARK: - Test inspection

    var queueDepth: Int { queued.count }
    var isInFlight: Bool { inFlight != nil }

    // MARK: - Internal

    private func pump() {
        guard inFlight == nil, !queued.isEmpty else { return }
        let next = queued.removeFirst()
        inFlightCancelled = false

        let llm = self.llm
        let config = configProvider()
        let apiKey = apiKeyProvider()
        let timeout = timeoutProvider()
        let storeRef = self.store

        let task = Task { [weak self] in
            let result: Result<[LLMStyleSuggestion], Error>
            do {
                let suggestions = try await withTimeout(seconds: timeout) {
                    await llm.analyze(
                        target: next.paragraph,
                        previousContext: nil,
                        nextContext: nil,
                        config: config,
                        apiKey: apiKey,
                        harperSpans: []
                    )
                }
                result = .success(suggestions)
            } catch {
                result = .failure(error)
            }

            await self?.finishInFlight(
                hash: next.hash,
                bundleID: next.bundleID,
                result: result,
                store: storeRef
            )
        }
        inFlight = InFlight(hash: next.hash, bundleID: next.bundleID, task: task)
    }

    private func finishInFlight(
        hash: ParagraphHash,
        bundleID: String,
        result: Result<[LLMStyleSuggestion], Error>,
        store: (any LLMRequestQueueStore)?
    ) async {
        let wasCancelled = inFlightCancelled
        inFlight = nil
        inFlightCancelled = false

        if !wasCancelled {
            await store?.handleQueueResponse(hash: hash, bundleID: bundleID, result: result)
        }
        pump()
    }
}
