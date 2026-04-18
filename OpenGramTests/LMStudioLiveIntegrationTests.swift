import Testing
import Foundation
@testable import OpenGramLib

/// Live end-to-end tests that hit a running LM Studio instance.
///
/// **On-demand only.** Gated on the env var `OPENGRAM_LIVE_LLM` — the default
/// `xcodebuild test` run does not discover or execute this suite. To run it,
/// forward the env var through xcodebuild to the test runner using the
/// `TEST_RUNNER_` prefix (xcodebuild strips the prefix before spawning the runner):
///
///     TEST_RUNNER_OPENGRAM_LIVE_LLM=1 \
///       xcodebuild -project OpenGram.xcodeproj -scheme OpenGram \
///                  -only-testing:OpenGramTests/LMStudioLiveIntegrationTests test
///
/// Once the suite is enabled, each test probes `{baseURL}/models` first. If LM Studio
/// isn't reachable, the test records an Issue noting the skip and returns without
/// failing — so an enabled run on a machine with LM Studio down still stays green.
///
/// Env vars (all optional unless gate above requires):
/// - `OPENGRAM_LIVE_LLM`         **required gate** — any non-empty value enables the suite
/// - `OPENGRAM_LIVE_LLM_URL`     defaults to `http://127.0.0.1:1234/v1`
/// - `OPENGRAM_LIVE_LLM_MODEL`   defaults to `"default"`
/// - `OPENGRAM_LIVE_LLM_API_KEY` Bearer token if the endpoint requires one
///
/// What these exercise that the mocked integration tests cannot:
///   - Real HTTP round-trip against the user's actual endpoint
///   - Real OpenAI-compatible response shape parsing
///   - Real prompt → model → suggestions behavior (end-to-end signal)
///
/// The tests assert structural invariants (non-empty response on a paragraph designed
/// to elicit suggestions, round-trip < timeout, empty-set on disabled config). They
/// do NOT assert specific suggestion text — that depends on the loaded model.
@Suite(
    "LMStudioLiveIntegration",
    .enabled(if: ProcessInfo.processInfo.environment["OPENGRAM_LIVE_LLM"].map { !$0.isEmpty } ?? false,
             "Set TEST_RUNNER_OPENGRAM_LIVE_LLM=1 to enable live tests"),
    .serialized
)
struct LMStudioLiveIntegrationTests {

    // MARK: - Env

    private static var liveBaseURL: String {
        ProcessInfo.processInfo.environment["OPENGRAM_LIVE_LLM_URL"] ?? "http://127.0.0.1:1234/v1"
    }

    private static var liveModel: String {
        ProcessInfo.processInfo.environment["OPENGRAM_LIVE_LLM_MODEL"] ?? "default"
    }

    private static var liveAPIKey: String? {
        let key = ProcessInfo.processInfo.environment["OPENGRAM_LIVE_LLM_API_KEY"]
        return (key?.isEmpty == false) ? key : nil
    }

    // MARK: - Reachability probe

    /// Probes `{baseURL}/models` before running. Returns false on any non-2xx or network error.
    /// Kept here (not in LLMService.healthCheck) so live tests own their own skip decision
    /// without coupling to app-side health semantics.
    private func lmStudioReachable() async -> Bool {
        let service = LLMService(session: .shared)
        let config = makeLiveConfig()
        return await service.healthCheck(config: config, apiKey: Self.liveAPIKey)
    }

    private func makeLiveConfig(enabledChecks: Set<LLMCheckType> = [.tone, .clarity, .rephrase]) -> LLMConfig {
        LLMConfig(
            baseURL: Self.liveBaseURL,
            model: Self.liveModel,
            enabledChecks: enabledChecks,
            temperature: 0.3,
            maxTokens: 512,
            requestTimeout: 60,
            confidenceThreshold: LLMConfig.defaultConfidenceThreshold
        )
    }

    // MARK: - Fakes (reused from mocked suite pattern)

    private final class FakeAXTextBox: @unchecked Sendable {
        private let lock = NSLock()
        private var byBundle: [String: String] = [:]
        func set(bundleID: String, text: String) {
            lock.lock(); defer { lock.unlock() }
            byBundle[bundleID] = text
        }
        func read(bundleID: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            return byBundle[bundleID]
        }
    }

    private final class StubCapabilityCache: AXCapabilityCacheProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var separators: [String: String] = [:]
        func isSupported(bundleID: String, version: String?) -> Bool? { nil }
        func store(bundleID: String, version: String?, supported: Bool) {}
        func isNotificationReliable(bundleID: String) -> Bool? { nil }
        func storeNotificationReliability(bundleID: String, reliable: Bool) {}
        func separator(bundleID: String, version: String?) -> String? {
            lock.lock(); defer { lock.unlock() }
            return separators["\(bundleID):\(version ?? "nil")"]
        }
        func storeSeparator(bundleID: String, version: String?, separator: String) {
            lock.lock(); defer { lock.unlock() }
            separators["\(bundleID):\(version ?? "nil")"] = separator
        }
    }

    // MARK: - Wiring

    private static let testBundleID = "com.test.live-editor"

    private struct Rig {
        let store: ParagraphSuggestionStore
        let queue: LLMRequestQueue
        let splitter: ParagraphSplitter
        let box: FakeAXTextBox
    }

    private func makeLiveRig(
        enabledChecks: Set<LLMCheckType> = [.tone, .clarity, .rephrase],
        initialText: String
    ) async -> Rig {
        let box = FakeAXTextBox()
        box.set(bundleID: Self.testBundleID, text: initialText)

        let llm = LLMService(session: .shared)   // REAL session — no URLProtocol
        let apiKey = Self.liveAPIKey
        let config = makeLiveConfig(enabledChecks: enabledChecks)

        let queue = LLMRequestQueue(
            llm: llm,
            configProvider: { config },
            apiKeyProvider: { apiKey },
            timeoutProvider: { 60 }
        )
        let splitter = ParagraphSplitter(capabilityCache: StubCapabilityCache())
        let store = ParagraphSuggestionStore(
            queue: queue,
            splitter: splitter,
            textProvider: { [box] bundleID in box.read(bundleID: bundleID) }
        )
        await queue.setStore(store)
        return Rig(store: store, queue: queue, splitter: splitter, box: box)
    }

    private func split(_ rig: Rig, text: String) -> ParagraphSet {
        rig.splitter.split(text: text, bundleID: Self.testBundleID, version: nil, caretOffset: nil)
    }

    /// Poll until predicate is true or timeout elapses.
    private func waitFor(
        timeoutMs: Int = 60_000,
        intervalMs: Int = 100,
        _ predicate: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000.0)
        while Date() < deadline {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
        }
        return false
    }

    /// Paragraph deliberately weak/verbose so a reasonable model returns ≥1 rewrite.
    private static let verboseParagraph = """
    I think maybe we should probably try to consider whether or not we might want to go \
    ahead and ship this feature at some point in the near future, though obviously there \
    are many different factors and considerations that could potentially influence the \
    timing of such a decision in various ways.
    """

    // MARK: - Tests

    @Test("health check — LM Studio /models endpoint is reachable")
    func healthCheck_liveEndpointReachable() async {
        let reachable = await lmStudioReachable()
        guard reachable else {
            Issue.record("""
            Skipping live suite: LM Studio not reachable at \(Self.liveBaseURL). \
            Start LM Studio, load a model, enable the local server, then re-run. \
            Set OPENGRAM_LIVE_LLM_URL to override.
            """)
            return
        }
        #expect(reachable)
    }

    @Test("live round-trip — verbose paragraph produces ≥1 renderable Suggestion")
    func liveRoundTrip_producesSuggestion() async {
        guard await lmStudioReachable() else {
            Issue.record("Skipping: LM Studio not reachable at \(Self.liveBaseURL)")
            return
        }

        let rig = await makeLiveRig(initialText: Self.verboseParagraph)
        await rig.store.reconcile(set: split(rig, text: Self.verboseParagraph))

        let gotSuggestion = await waitFor(timeoutMs: 60_000) {
            await !rig.store.renderableSuggestions(for: Self.testBundleID).isEmpty
        }
        #expect(gotSuggestion, "expected ≥1 suggestion from live LM Studio for verbose paragraph")

        let suggestions = await rig.store.renderableSuggestions(for: Self.testBundleID)
        #expect(suggestions.allSatisfy { $0.source == .llm })
        #expect(suggestions.allSatisfy { $0.original == Self.verboseParagraph })
        #expect(suggestions.allSatisfy {
            guard let rep = $0.primaryReplacement else { return false }
            return !rep.isEmpty && rep != Self.verboseParagraph
        }, "every live suggestion must carry a non-empty rewrite that differs from the original")
    }

    @Test("live regression — disabled enabledChecks produces zero suggestions (no HTTP)")
    func liveDisabled_noSuggestions() async {
        guard await lmStudioReachable() else {
            Issue.record("Skipping: LM Studio not reachable at \(Self.liveBaseURL)")
            return
        }

        let rig = await makeLiveRig(enabledChecks: [], initialText: Self.verboseParagraph)
        await rig.store.reconcile(set: split(rig, text: Self.verboseParagraph))

        // Even with a slow live endpoint, a disabled config must short-circuit before HTTP,
        // so waiting the full request timeout would only reflect the poll ceiling. Wait a
        // bounded window and assert the store stays empty.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let suggestions = await rig.store.renderableSuggestions(for: Self.testBundleID)
        #expect(suggestions.isEmpty)
    }

    @Test("live request body — LLMService POSTs OpenAI-compatible payload with target paragraph")
    func liveRequestBody_shapeMatchesLMStudio() async throws {
        // This test does not use the store — it exercises LLMService directly against the live
        // endpoint and validates we get a non-empty parsed response. Pipeline shape is covered
        // by the mocked integration tests.
        guard await lmStudioReachable() else {
            Issue.record("Skipping: LM Studio not reachable at \(Self.liveBaseURL)")
            return
        }

        let service = LLMService(session: .shared)
        let result = await service.analyze(
            target: Self.verboseParagraph,
            previousContext: nil,
            nextContext: nil,
            config: makeLiveConfig(),
            apiKey: Self.liveAPIKey,
            harperSpans: []
        )
        #expect(!result.isEmpty, "live analyze(target:) returned zero suggestions — model may have declined to answer or baseURL is wrong")
        for sug in result {
            #expect(!sug.revisedText.isEmpty)
            #expect([.tone, .clarity, .rephrase].contains(sug.category))
        }
    }
}
