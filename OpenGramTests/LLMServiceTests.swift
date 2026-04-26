import Testing
import Foundation
@testable import OpenGramLib

@Suite("LLMService")
struct LLMServiceTests {

    // MARK: - JSON Parsing (unified response format)

    @Test("parses valid 2-suggestion response")
    func parseValidTwoSuggestionResponse() async {
        let service = LLMService()
        let json = """
        {
          "suggestions": [
            {"category": "tone", "revised_text": "We will deliver.", "explanation": "More confident.", "confidence": 9},
            {"category": "rephrase", "revised_text": "Ship it.", "explanation": "Concise rewrite.", "confidence": 10}
          ]
        }
        """
        let paragraph = "We should probably try to be direct about this."
        let suggestions = await service.parseJSONContent(json, paragraph: paragraph)
        #expect(suggestions.count == 2)
        #expect(suggestions[0].category == .tone)
        #expect(suggestions[1].category == .rephrase)
    }

    @Test("returns empty array when suggestions array is empty")
    func parseEmptySuggestionsArray() async {
        let service = LLMService()
        let json = """
        {"suggestions": []}
        """
        let suggestions = await service.parseJSONContent(json, paragraph: "This text is fine.")
        #expect(suggestions.isEmpty)
    }

    @Test("returns empty array on malformed JSON")
    func parseMalformedJSONReturnsEmpty() async {
        let service = LLMService()
        let suggestions = await service.parseJSONContent("This is not JSON at all.", paragraph: "Some text.")
        #expect(suggestions.isEmpty)
    }

    @Test("strips markdown fences before parsing")
    func parseMarkdownFencedJSON() async {
        let service = LLMService()
        let json = """
        ```json
        {"suggestions": [{"category": "tone", "revised_text": "Be direct.", "explanation": "Hedging removed.", "confidence": 9}]}
        ```
        """
        let suggestions = await service.parseJSONContent(json, paragraph: "I think maybe we could be direct.")
        #expect(suggestions.count == 1)
        #expect(suggestions[0].category == .tone)
    }

    @Test("strips preamble before first brace")
    func parsePreambleBeforeObject() async {
        let service = LLMService()
        let json = """
        Here are my suggestions:
        {"suggestions": [{"category": "tone", "revised_text": "Short text.", "explanation": "Simplified.", "confidence": 9}]}
        """
        let suggestions = await service.parseJSONContent(json, paragraph: "Some unnecessarily verbose text here.")
        #expect(suggestions.count == 1)
    }

    @Test("filters suggestions with confidence below default threshold")
    func filtersLowConfidenceSuggestions() async {
        let service = LLMService()
        let json = """
        {
          "suggestions": [
            {"category": "rephrase", "revised_text": "Clear.", "explanation": "Better.", "confidence": 8},
            {"category": "tone", "revised_text": "Direct.", "explanation": "Confident.", "confidence": 9}
          ]
        }
        """
        let suggestions = await service.parseJSONContent(json, paragraph: "Some text.")
        #expect(suggestions.count == 1)
        #expect(suggestions[0].category == .tone)
    }

    @Test("returns empty array for empty input")
    func parseEmptyStringReturnsEmpty() async {
        let service = LLMService()
        let suggestions = await service.parseJSONContent("", paragraph: "")
        #expect(suggestions.isEmpty)
    }

    @Test("LLMService drops category=clarity entries end-to-end (markdown-fence + DTO drop integration). Complements DTO-layer coverage at LLMResponseDTOTests.clarityCategoryDroppedPostDeletion_CLAR09. CLAR-21.")
    func parseClarityCategoryDropped_CLAR21() async {
        let service = LLMService()
        let json = """
        ```json
        {"suggestions": [
          {"category": "clarity", "revised_text": "X", "explanation": "E1", "confidence": 9},
          {"category": "tone", "revised_text": "Y", "explanation": "E2", "confidence": 9}
        ]}
        ```
        """
        let suggestions = await service.parseJSONContent(json, paragraph: "Original text.")
        #expect(suggestions.count == 1, "clarity entry must be dropped; only tone remains")
        #expect(suggestions.first?.category == .tone)
    }

    // MARK: - Cancellation

    @Test("new analyze() call cancels in-flight request")
    func newAnalyzeCancelsPreviousTask() async {
        // Inject a mock session that never responds (hangs indefinitely)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = LLMService(session: session)

        let llmConfig = LLMConfig(
            baseURL: "http://localhost:1234/v1",
            model: "test",
            enabledChecks: [.tone],
            temperature: 0.3,
            maxTokens: 512,
            requestTimeout: 30,
            confidenceThreshold: LLMConfig.defaultConfidenceThreshold
        )

        // First call — will hang because HangingURLProtocol never responds
        let firstTask = Task {
            await service.analyze(paragraph: "First paragraph", config: llmConfig, apiKey: nil)
        }

        // Give the first task a moment to start
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Second call — cancels the first and starts fresh; returns [] because URL is unreachable
        let secondResult = await service.analyze(paragraph: "Second paragraph", config: llmConfig, apiKey: nil)

        firstTask.cancel()
        #expect(secondResult.isEmpty, "analyze() returns empty array when network is unavailable")
    }

    @Test("returns empty array on network error")
    func returnsEmptyArrayOnNetworkError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = LLMService(session: session)

        let llmConfig = LLMConfig(
            baseURL: "http://localhost:1234/v1",
            model: "test",
            enabledChecks: [.tone],
            temperature: 0.3,
            maxTokens: 512,
            requestTimeout: 5,
            confidenceThreshold: LLMConfig.defaultConfidenceThreshold
        )

        let result = await service.analyze(paragraph: "Some text.", config: llmConfig, apiKey: nil)
        #expect(result.isEmpty)
    }

    // MARK: - LLMConfig

    @Test func configDefaultValues() {
        let config = LLMConfig.default
        #expect(config.baseURL == "http://localhost:1234/v1")
        #expect(config.temperature == 0.3)
        #expect(config.maxTokens == 1024)
        #expect(config.enabledChecks.count == 2)
        #expect(config.enabledChecks.contains(.tone))
        #expect(config.enabledChecks.contains(.rephrase))
    }

    @Test func configIsEnabledFalseWhenURLEmpty() {
        var config = LLMConfig.default
        config.baseURL = ""
        #expect(!config.isEnabled)
    }

    @Test func configIsEnabledFalseWhenNoChecks() {
        var config = LLMConfig.default
        config.enabledChecks = []
        #expect(!config.isEnabled)
    }

    @Test func configChatCompletionsURL() {
        let config = LLMConfig.default
        #expect(config.chatCompletionsURL?.absoluteString == "http://localhost:1234/v1/chat/completions")
    }

    @Test func configChatCompletionsURLStripsTrailingSlash() {
        var config = LLMConfig.default
        config.baseURL = "http://localhost:1234/v1/"
        #expect(config.chatCompletionsURL?.absoluteString == "http://localhost:1234/v1/chat/completions")
    }
}

// MARK: - Test Helpers

/// URLProtocol that immediately fails every request with a connection error.
private final class FailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }

    override func stopLoading() {}
}

/// URLProtocol that never responds — simulates an in-flight request that never completes.
private final class HangingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

// MARK: - Target Context Tests

/// Records every request it sees; responds with a canned body + status.
private final class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var cannedStatus: Int = 200
    nonisolated(unsafe) static var cannedBody: Data = Data()
    nonisolated(unsafe) static var receivedRequests: [URLRequest] = []
    nonisolated(unsafe) static var receivedBodies: [Data] = []
    nonisolated(unsafe) static var didLoadAny: Bool = false

    static func reset() {
        cannedStatus = 200
        cannedBody = Data()
        receivedRequests = []
        receivedBodies = []
        didLoadAny = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.didLoadAny = true
        Self.receivedRequests.append(request)
        // URLProtocol strips httpBody in some flows; grab via bodyStreamData if needed.
        if let body = request.httpBody {
            Self.receivedBodies.append(body)
        } else if let stream = request.httpBodyStream {
            stream.open()
            var buf = Data()
            let bufferSize = 4096
            var rawBuf = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let n = stream.read(&rawBuf, maxLength: bufferSize)
                if n <= 0 { break }
                buf.append(rawBuf, count: n)
            }
            stream.close()
            Self.receivedBodies.append(buf)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.cannedStatus,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.cannedBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeRecordingSession() -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [RecordingURLProtocol.self]
    return URLSession(configuration: cfg)
}

private func makeEnabledConfig() -> LLMConfig {
    LLMConfig(
        baseURL: "http://localhost:1234/v1",
        model: "test",
        enabledChecks: [.tone, .rephrase],
        temperature: 0.3,
        maxTokens: 512,
        requestTimeout: 30,
        confidenceThreshold: LLMConfig.defaultConfidenceThreshold
    )
}

private let fixtureTarget = "The target paragraph text."
private let fixturePrevious = "Earlier."
private let fixtureNext = "Later."

private let cannedOneSuggestionEnvelope: Data = {
    let content = """
    {"suggestions":[{"category":"tone","revised_text":"Direct version.","explanation":"More confident.","confidence":9}]}
    """
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let envelope = """
    {"choices":[{"message":{"content":"\(escaped)"}}]}
    """
    return envelope.data(using: .utf8)!
}()

@Suite("LLMService.analyze(target:)", .serialized)
struct LLMServiceTargetTests {

    @Test("disabled config returns empty and does not hit session")
    func analyze_target_disabledConfig_returnsEmpty() async {
        RecordingURLProtocol.reset()
        let session = makeRecordingSession()
        let service = LLMService(session: session)
        var config = makeEnabledConfig()
        config.baseURL = ""   // isEnabled = false

        let result = await service.analyze(
            target: fixtureTarget,
            previousContext: fixturePrevious,
            nextContext: fixtureNext,
            config: config,
            apiKey: nil,
            harperSpans: []
        )

        #expect(result.isEmpty)
        #expect(RecordingURLProtocol.didLoadAny == false)
    }

    @Test("invalid URL returns empty")
    func analyze_target_invalidURL_returnsEmpty() async {
        RecordingURLProtocol.reset()
        let session = makeRecordingSession()
        let service = LLMService(session: session)
        var config = makeEnabledConfig()
        config.baseURL = "   "   // whitespace -> chatCompletionsURL nil, but isEnabled may still be true

        let result = await service.analyze(
            target: fixtureTarget,
            previousContext: nil,
            nextContext: nil,
            config: config,
            apiKey: nil,
            harperSpans: []
        )
        #expect(result.isEmpty)
    }

    @Test("HTTP non-2xx returns empty")
    func analyze_target_httpNon2xx_returnsEmpty() async {
        RecordingURLProtocol.reset()
        RecordingURLProtocol.cannedStatus = 500
        RecordingURLProtocol.cannedBody = Data("error".utf8)
        let session = makeRecordingSession()
        let service = LLMService(session: session)

        let result = await service.analyze(
            target: fixtureTarget,
            previousContext: fixturePrevious,
            nextContext: fixtureNext,
            config: makeEnabledConfig(),
            apiKey: nil,
            harperSpans: []
        )
        #expect(result.isEmpty)
    }

    @Test("parses suggestions with target as originalText")
    func analyze_target_parsesSuggestionsWithTargetAsOriginalText() async {
        RecordingURLProtocol.reset()
        RecordingURLProtocol.cannedStatus = 200
        RecordingURLProtocol.cannedBody = cannedOneSuggestionEnvelope
        let session = makeRecordingSession()
        let service = LLMService(session: session)

        let result = await service.analyze(
            target: fixtureTarget,
            previousContext: fixturePrevious,
            nextContext: fixtureNext,
            config: makeEnabledConfig(),
            apiKey: nil,
            harperSpans: []
        )
        #expect(result.count == 1)
        #expect(result.first?.originalText == fixtureTarget)
        #expect(result.first?.category == .tone)
    }

    @Test("user message uses incremental prompt shape with <none> for nil context")
    func analyze_target_userMessageIsIncrementalShape() async throws {
        RecordingURLProtocol.reset()
        RecordingURLProtocol.cannedStatus = 200
        RecordingURLProtocol.cannedBody = cannedOneSuggestionEnvelope
        let session = makeRecordingSession()
        let service = LLMService(session: session)

        _ = await service.analyze(
            target: fixtureTarget,
            previousContext: nil,
            nextContext: fixtureNext,
            config: makeEnabledConfig(),
            apiKey: nil,
            harperSpans: []
        )

        #expect(RecordingURLProtocol.receivedBodies.count == 1)
        let body = RecordingURLProtocol.receivedBodies.first ?? Data()
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        #expect(bodyString.contains("Previous paragraph (context only"))
        #expect(bodyString.contains("Target paragraph (provide suggestions"))
        #expect(bodyString.contains("Following paragraph (context only"))
        #expect(bodyString.contains("<none>"))
        #expect(bodyString.contains(fixtureTarget))
        #expect(bodyString.contains(fixtureNext))
    }

    @Test("cancellation returns empty without throwing")
    func analyze_target_cancellation_returnsEmpty() async {
        // Hanging protocol so the request never resolves on its own.
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [HangingURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let service = LLMService(session: session)

        let task = Task {
            await service.analyze(
                target: fixtureTarget,
                previousContext: fixturePrevious,
                nextContext: fixtureNext,
                config: makeEnabledConfig(),
                apiKey: nil,
                harperSpans: []
            )
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        let result = await task.value
        #expect(result.isEmpty)
    }

    @Test("legacy analyze(paragraph:) signature unchanged — regression guard")
    func analyze_paragraph_legacySignatureUnchanged() async {
        RecordingURLProtocol.reset()
        RecordingURLProtocol.cannedStatus = 200
        RecordingURLProtocol.cannedBody = cannedOneSuggestionEnvelope
        let session = makeRecordingSession()
        let service = LLMService(session: session)

        let result = await service.analyze(
            paragraph: "Legacy full-text path.",
            config: makeEnabledConfig(),
            apiKey: nil,
            harperSpans: []
        )
        #expect(result.count == 1)
        #expect(result.first?.originalText == "Legacy full-text path.")
    }
}
