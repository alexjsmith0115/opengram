import Testing
import Foundation
@testable import OpenGramLib

/// End-to-end integration: simulated AX text input → ParagraphSuggestionStore →
/// LLMRequestQueue → real LLMService → URLSession (mocked via URLProtocol) → response
/// → store state → renderableSuggestions.
///
/// Catches config-gate regressions where a disabled LLMConfig silently swallows all
/// requests, producing zero HTTP traffic and zero suggestions.
@Suite("LMStudioPipelineIntegration", .serialized)
struct LMStudioPipelineIntegrationTests {

    // MARK: - AX input mock

    /// Thread-safe text store that mimics what AX would read from the focused element.
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

    // MARK: - LM Studio HTTP mock

    /// URLProtocol that emulates LM Studio's OpenAI-compatible /v1/chat/completions.
    /// Records every incoming request and replies with a canned suggestion envelope.
    private final class LMStudioMockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var cannedStatus: Int = 200
        nonisolated(unsafe) static var cannedContent: String = ""
        nonisolated(unsafe) static var receivedRequests: [URLRequest] = []
        nonisolated(unsafe) static var receivedBodies: [Data] = []
        nonisolated(unsafe) static var requestCount: Int = 0
        nonisolated(unsafe) static var responseDelayMs: Int = 0

        static func reset() {
            cannedStatus = 200
            cannedContent = ""
            receivedRequests = []
            receivedBodies = []
            requestCount = 0
            responseDelayMs = 0
        }

        /// Convenience: wrap a suggestions JSON payload in an OpenAI chat-completions envelope.
        static func setCannedSuggestions(_ payload: String) {
            let escaped = payload
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            cannedContent = "{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}"
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requestCount += 1
            Self.receivedRequests.append(request)
            if let body = request.httpBody {
                Self.receivedBodies.append(body)
            } else if let stream = request.httpBodyStream {
                stream.open()
                var buf = Data()
                var rawBuf = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&rawBuf, maxLength: rawBuf.count)
                    if n <= 0 { break }
                    buf.append(rawBuf, count: n)
                }
                stream.close()
                Self.receivedBodies.append(buf)
            }
            // Hold the URLProtocol worker thread before delivering — simulates a slow LM
            // Studio response so tests can mutate state mid-flight.
            if Self.responseDelayMs > 0 {
                Thread.sleep(forTimeInterval: TimeInterval(Self.responseDelayMs) / 1000.0)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: Self.cannedStatus,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(Self.cannedContent.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    // MARK: - Wiring helpers

    private static let testBundleID = "com.test.editor"
    private static let testBaseURL = "http://127.0.0.1:1234/v1"

    private struct Rig {
        let store: ParagraphSuggestionStore
        let queue: LLMRequestQueue
        let splitter: ParagraphSplitter
        let box: FakeAXTextBox
    }

    private func makeRig(
        enabledChecks: Set<LLMCheckType> = [.tone, .rephrase],
        baseURL: String = testBaseURL,
        initialText: String
    ) async -> Rig {
        LMStudioMockURLProtocol.reset()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [LMStudioMockURLProtocol.self]
        let session = URLSession(configuration: cfg)

        let box = FakeAXTextBox()
        box.set(bundleID: Self.testBundleID, text: initialText)

        let llm = LLMService(session: session)
        let queue = LLMRequestQueue(
            llm: llm,
            configProvider: {
                LLMConfig(
                    baseURL: baseURL,
                    model: "test-model",
                    enabledChecks: enabledChecks,
                    temperature: 0.3,
                    maxTokens: 512,
                    requestTimeout: 5,
                    confidenceThreshold: LLMConfig.defaultConfidenceThreshold
                )
            },
            apiKeyProvider: { nil },
            timeoutProvider: { 5 }
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

    /// Makes a ParagraphSet from the splitter for a given bundleID + text.
    private func split(_ rig: Rig, text: String) -> ParagraphSet {
        rig.splitter.split(text: text, bundleID: Self.testBundleID, version: nil, caretOffset: nil)
    }

    /// Polls until `predicate` is true or timeout elapses. Returns false on timeout.
    private func waitFor(
        timeoutMs: Int = 2000,
        intervalMs: Int = 20,
        _ predicate: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutMs) / 1000.0)
        while Date() < deadline {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
        }
        return false
    }

    private static let canned2SuggestionsJSON = """
    {"suggestions":[{"category":"tone","revised_text":"Be direct about the deliverable.","explanation":"More confident.","confidence":9},{"category":"rephrase","revised_text":"Ship it.","explanation":"Concise rewrite.","confidence":7}]}
    """

    // MARK: - Tests

    @Test("happy path — enabled config fires HTTP request, response renders as Suggestion")
    func happyPath_enabledConfig_producesSuggestion() async {
        let paragraph = "We should probably try to be direct about the deliverable here."
        let rig = await makeRig(initialText: paragraph)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)

        await rig.store.reconcile(set: split(rig, text: paragraph))

        let gotHTTP = await waitFor { LMStudioMockURLProtocol.requestCount >= 1 }
        #expect(gotHTTP, "expected ≥1 HTTP request to /v1/chat/completions")

        let rendered = await waitFor {
            await !rig.store.renderableSuggestions(for: Self.testBundleID).isEmpty
        }
        #expect(rendered, "store never produced a renderable suggestion")

        let suggestions = await rig.store.renderableSuggestions(for: Self.testBundleID)
        #expect(suggestions.count == 1)
        #expect(suggestions.first?.source == .llm)
        #expect(suggestions.first?.original == paragraph)
    }

    @Test("disabled checks (regression for silent-skip bug) — zero HTTP requests")
    func disabledChecks_emptySet_blocksAllHTTP() async {
        let paragraph = "This paragraph is long enough to pass the minimum length gate."
        let rig = await makeRig(enabledChecks: [], initialText: paragraph)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)

        await rig.store.reconcile(set: split(rig, text: paragraph))

        // Give the queue time to pump. If a request were going to fire, it would fire here.
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(LMStudioMockURLProtocol.requestCount == 0,
                "disabled config must not produce any HTTP traffic")
        let rendered = await rig.store.renderableSuggestions(for: Self.testBundleID)
        #expect(rendered.isEmpty)
    }

    @Test("empty baseURL — zero HTTP requests")
    func emptyBaseURL_blocksAllHTTP() async {
        let paragraph = "This paragraph is long enough to pass the minimum length gate."
        let rig = await makeRig(baseURL: "", initialText: paragraph)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)

        await rig.store.reconcile(set: split(rig, text: paragraph))
        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(LMStudioMockURLProtocol.requestCount == 0)
    }

    @Test("request body shape — POST to /v1/chat/completions with model + messages + target text")
    func requestBody_matchesLMStudioExpectedShape() async throws {
        let paragraph = "This paragraph must appear verbatim in the request body."
        let rig = await makeRig(initialText: paragraph)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)

        await rig.store.reconcile(set: split(rig, text: paragraph))
        _ = await waitFor { LMStudioMockURLProtocol.requestCount >= 1 }

        let request = try #require(LMStudioMockURLProtocol.receivedRequests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "\(Self.testBaseURL)/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(LMStudioMockURLProtocol.receivedBodies.first)
        let bodyString = try #require(String(data: body, encoding: .utf8))
        #expect(bodyString.contains("\"model\":\"test-model\""))
        #expect(bodyString.contains("\"messages\""))
        #expect(bodyString.contains(paragraph),
                "request body must include the target paragraph verbatim")
    }

    @Test("HTTP 500 — failure propagates to store, no renderable suggestion")
    func httpError_failsGracefully() async {
        let paragraph = "This is a paragraph long enough to trigger a request."
        let rig = await makeRig(initialText: paragraph)
        LMStudioMockURLProtocol.cannedStatus = 500
        LMStudioMockURLProtocol.cannedContent = "internal error"

        await rig.store.reconcile(set: split(rig, text: paragraph))
        _ = await waitFor { LMStudioMockURLProtocol.requestCount >= 1 }

        // Wait for response to settle through store.
        try? await Task.sleep(nanoseconds: 200_000_000)
        let suggestions = await rig.store.renderableSuggestions(for: Self.testBundleID)
        #expect(suggestions.isEmpty, "HTTP 500 must not produce renderable suggestion")
    }

    @Test("text mutated before response — verify-on-response drops stale entry")
    func textMutatedMidFlight_dropsStaleEntry() async {
        let original = "The original paragraph long enough to exceed thirty characters easily."
        let rig = await makeRig(initialText: original)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)
        // Hold the HTTP response long enough to mutate the text box before the store's
        // handleQueueResponse callback re-reads via textProvider.
        LMStudioMockURLProtocol.responseDelayMs = 200

        await rig.store.reconcile(set: split(rig, text: original))
        _ = await waitFor { LMStudioMockURLProtocol.requestCount >= 1 }

        // Mutate AX text while the response is in flight — verify-on-response re-reads,
        // re-splits, and finds the original hash absent, so the entry is dropped.
        let mutated = "A completely different paragraph replacing the first one entirely now."
        rig.box.set(bundleID: Self.testBundleID, text: mutated)

        // Wait past the delayed response + store callback.
        try? await Task.sleep(nanoseconds: 600_000_000)

        let suggestions = await rig.store.renderableSuggestions(for: Self.testBundleID)
        #expect(suggestions.isEmpty,
                "verify-on-response must drop suggestion for paragraph that no longer exists")
    }

    @Test("short paragraph below minParagraphLength — no HTTP request")
    func shortParagraph_belowLengthGate_skipsRequest() async {
        let shortText = "Too short."   // below default 30-char threshold
        let rig = await makeRig(initialText: shortText)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)

        await rig.store.reconcile(set: split(rig, text: shortText))
        try? await Task.sleep(nanoseconds: 150_000_000)

        #expect(LMStudioMockURLProtocol.requestCount == 0,
                "paragraph below minParagraphLength must not trigger HTTP")
    }

    @Test("store emits ≥2 suggestionsChanged events across the reconcile → response arc")
    func storeEmitsEventsAcrossReconcileAndResponse() async {
        let paragraph = "This paragraph is long enough to trigger an LLM call and event."
        let rig = await makeRig(initialText: paragraph)
        LMStudioMockURLProtocol.setCannedSuggestions(Self.canned2SuggestionsJSON)

        // Subscribe BEFORE reconcile so we catch every emission.
        let events = rig.store.events
        let collector = Task { () -> Int in
            var count = 0
            for await _ in events {
                count += 1
                if count >= 2 { break }   // reconcile emits 1, response-lands emits 1
            }
            return count
        }

        await rig.store.reconcile(set: split(rig, text: paragraph))

        // Wait for the collector to observe both events.
        let collectedResult: Int? = await withTaskGroup(of: Int?.self) { group in
            group.addTask { await collector.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                collector.cancel()
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        #expect(collectedResult == 2, "store must emit both reconcile event and response-lands event")
    }
}
