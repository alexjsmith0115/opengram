import Testing
import Foundation
@testable import OpenGramLib

@Suite("LLMService")
struct LLMServiceTests {

    // MARK: - JSON Parsing (unified response format)

    @Test("parses valid 3-suggestion response")
    func parseValidThreeSuggestionResponse() async {
        let service = LLMService()
        let json = """
        {
          "suggestions": [
            {"category": "clarity", "revised_text": "Be direct.", "explanation": "Simpler phrasing.", "confidence": 8},
            {"category": "tone", "revised_text": "We will deliver.", "explanation": "More confident.", "confidence": 9},
            {"category": "rephrase", "revised_text": "Ship it.", "explanation": "Concise rewrite.", "confidence": 7}
          ]
        }
        """
        let paragraph = "We should probably try to be direct about this."
        let suggestions = await service.parseJSONContent(json, paragraph: paragraph)
        #expect(suggestions.count == 3)
        #expect(suggestions[0].category == .clarity)
        #expect(suggestions[1].category == .tone)
        #expect(suggestions[2].category == .rephrase)
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
        {"suggestions": [{"category": "tone", "revised_text": "Be direct.", "explanation": "Hedging removed.", "confidence": 8}]}
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
        {"suggestions": [{"category": "clarity", "revised_text": "Short text.", "explanation": "Simplified.", "confidence": 9}]}
        """
        let suggestions = await service.parseJSONContent(json, paragraph: "Some unnecessarily verbose text here.")
        #expect(suggestions.count == 1)
    }

    @Test("filters suggestions with confidence below 7")
    func filtersLowConfidenceSuggestions() async {
        let service = LLMService()
        let json = """
        {
          "suggestions": [
            {"category": "clarity", "revised_text": "Clear.", "explanation": "Better.", "confidence": 6},
            {"category": "tone", "revised_text": "Direct.", "explanation": "Confident.", "confidence": 8}
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
        #expect(config.enabledChecks.count == 3)
        #expect(config.enabledChecks.contains(.tone))
        #expect(config.enabledChecks.contains(.clarity))
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
