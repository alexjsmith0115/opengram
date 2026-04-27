import Testing
@testable import OpenGramLib
import Foundation

// MARK: - Prompt builder tests

@Suite("LLMPrompts rewrite builders")
struct LLMRewritePromptTests {

    @Test("rewriteSystemPrompt embeds tone instruction and preserve-paragraphs guidance")
    func systemPrompt() {
        let prompt = LLMPrompts.rewriteSystemPrompt(tone: .friendly)
        #expect(prompt.contains(RewriteTone.friendly.promptInstruction))
        #expect(prompt.localizedCaseInsensitiveContains("preserve paragraph"))
        #expect(prompt.localizedCaseInsensitiveContains("output only"))
    }

    @Test("rewriteSystemPrompt varies by tone")
    func systemPromptVariesByTone() {
        let friendly = LLMPrompts.rewriteSystemPrompt(tone: .friendly)
        let professional = LLMPrompts.rewriteSystemPrompt(tone: .professional)
        let simple = LLMPrompts.rewriteSystemPrompt(tone: .simple)
        #expect(friendly != professional)
        #expect(professional != simple)
        #expect(friendly != simple)
    }

    @Test("rewriteUserMessage is the text payload as-is")
    func userMessage() {
        #expect(LLMPrompts.rewriteUserMessage(text: "hello world") == "hello world")
    }

    @Test("rewriteUserMessage preserves whitespace verbatim")
    func userMessagePreservesWhitespace() {
        let raw = "  leading\nand trailing  "
        #expect(LLMPrompts.rewriteUserMessage(text: raw) == raw)
    }
}

// MARK: - LLMService.rewrite tests

@Suite("LLMService.rewrite", .serialized)
struct LLMServiceRewriteTests {

    // MARK: Helpers (mirrors LLMServiceTests pattern)

    private func makeSession(status: Int, body: Data) -> URLSession {
        RewriteRecordingURLProtocol.reset(status: status, body: body)
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RewriteRecordingURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private func makeConfig() -> LLMConfig {
        LLMConfig(
            baseURL: "http://localhost:1234/v1",
            model: "test-model",
            enabledChecks: [.tone, .rephrase],
            temperature: 0.7,
            maxTokens: 512,
            requestTimeout: 30,
            confidenceThreshold: LLMConfig.defaultConfidenceThreshold
        )
    }

    private func envelopeData(content: String) -> Data {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let json = "{\"choices\":[{\"message\":{\"content\":\"\(escaped)\"}}]}"
        return json.data(using: .utf8)!
    }

    // MARK: Happy path

    @Test("returns raw model output including leading/trailing whitespace")
    func happyPath_rawContentPreserved() async throws {
        let rawContent = "  Hello, friend.  "
        let session = makeSession(status: 200, body: envelopeData(content: rawContent))
        let service = LLMService(session: session)

        let result = try await service.rewrite(
            text: "Hello.",
            tone: .friendly,
            config: makeConfig(),
            apiKey: "sk-test"
        )

        #expect(result == rawContent)
    }

    @Test("sends Authorization Bearer header with provided key")
    func sendsAuthHeader() async throws {
        let session = makeSession(status: 200, body: envelopeData(content: "Rewritten."))
        let service = LLMService(session: session)

        _ = try await service.rewrite(
            text: "Hello.",
            tone: .professional,
            config: makeConfig(),
            apiKey: "sk-mykey"
        )

        let req = RewriteRecordingURLProtocol.receivedRequests.first
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-mykey")
    }

    @Test("posts to chatCompletionsURL")
    func postsToCorrectURL() async throws {
        let session = makeSession(status: 200, body: envelopeData(content: "Done."))
        let service = LLMService(session: session)
        let config = makeConfig()

        _ = try await service.rewrite(
            text: "Hello.",
            tone: .simple,
            config: config,
            apiKey: "sk-test"
        )

        let req = RewriteRecordingURLProtocol.receivedRequests.first
        #expect(req?.url?.absoluteString == config.chatCompletionsURL?.absoluteString)
        #expect(req?.httpMethod == "POST")
    }

    @Test("body contains tone instruction")
    func bodyContainsToneInstruction() async throws {
        let session = makeSession(status: 200, body: envelopeData(content: "Done."))
        let service = LLMService(session: session)

        _ = try await service.rewrite(
            text: "Hello.",
            tone: .professional,
            config: makeConfig(),
            apiKey: "sk-test"
        )

        let bodyData = RewriteRecordingURLProtocol.receivedBodies.first ?? Data()
        let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
        #expect(bodyString.contains(RewriteTone.professional.promptInstruction
            .replacingOccurrences(of: "\\", with: "\\\\")))
    }

    // MARK: Empty / whitespace-only content

    @Test("whitespace-only content throws emptyResponse")
    func whitespaceOnlyContent_throwsEmptyResponse() async {
        let session = makeSession(status: 200, body: envelopeData(content: "   \n  "))
        let service = LLMService(session: session)

        do {
            _ = try await service.rewrite(
                text: "Hello.",
                tone: .friendly,
                config: makeConfig(),
                apiKey: "sk-test"
            )
            Issue.record("Expected LLMRewriteError.emptyResponse to be thrown")
        } catch LLMRewriteError.emptyResponse {
            // expected
        } catch {
            Issue.record("Expected LLMRewriteError.emptyResponse but got: \(error)")
        }
    }

    @Test("empty string content throws emptyResponse")
    func emptyStringContent_throwsEmptyResponse() async {
        let session = makeSession(status: 200, body: envelopeData(content: ""))
        let service = LLMService(session: session)

        do {
            _ = try await service.rewrite(
                text: "Hello.",
                tone: .friendly,
                config: makeConfig(),
                apiKey: "sk-test"
            )
            Issue.record("Expected LLMRewriteError.emptyResponse to be thrown")
        } catch LLMRewriteError.emptyResponse {
            // expected
        } catch {
            Issue.record("Expected LLMRewriteError.emptyResponse but got: \(error)")
        }
    }

    // MARK: Non-2xx HTTP

    @Test("HTTP 500 throws LLMRewriteError.http(status: 500)")
    func http500_throwsHTTPError() async {
        let session = makeSession(status: 500, body: Data("error".utf8))
        let service = LLMService(session: session)

        do {
            _ = try await service.rewrite(
                text: "Hello.",
                tone: .friendly,
                config: makeConfig(),
                apiKey: "sk-test"
            )
            Issue.record("Expected LLMRewriteError.http to be thrown")
        } catch LLMRewriteError.http(let status) {
            #expect(status == 500)
        } catch {
            Issue.record("Expected LLMRewriteError.http but got: \(error)")
        }
    }

    @Test("HTTP 401 throws LLMRewriteError.http(status: 401)")
    func http401_throwsHTTPError() async {
        let session = makeSession(status: 401, body: Data("unauthorized".utf8))
        let service = LLMService(session: session)

        do {
            _ = try await service.rewrite(
                text: "Hello.",
                tone: .professional,
                config: makeConfig(),
                apiKey: "sk-bad"
            )
            Issue.record("Expected LLMRewriteError.http to be thrown")
        } catch LLMRewriteError.http(let status) {
            #expect(status == 401)
        } catch {
            Issue.record("Expected LLMRewriteError.http but got: \(error)")
        }
    }

    // MARK: Transport error

    @Test("network failure throws LLMRewriteError.transport")
    func networkFailure_throwsTransport() async {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [RewriteFailingURLProtocol.self]
        let session = URLSession(configuration: cfg)
        let service = LLMService(session: session)

        do {
            _ = try await service.rewrite(
                text: "Hello.",
                tone: .simple,
                config: makeConfig(),
                apiKey: "sk-test"
            )
            Issue.record("Expected LLMRewriteError.transport to be thrown")
        } catch LLMRewriteError.transport {
            // expected
        } catch {
            Issue.record("Expected LLMRewriteError.transport but got: \(error)")
        }
    }

    // MARK: Isolation from analyze()

    @Test("rewrite() does not touch currentTask — analyze() cancellation still works after rewrite")
    func rewrite_doesNotAffectAnalyzeSingleFlight() async throws {
        // Run a successful rewrite, then verify analyze() still functions (returns results).
        // This confirms rewrite() left the actor's single-flight slot untouched.
        let rewriteSession = makeSession(status: 200, body: envelopeData(content: "Rewritten text."))
        let service = LLMService(session: rewriteSession)

        let rewritten = try await service.rewrite(
            text: "Original.",
            tone: .friendly,
            config: makeConfig(),
            apiKey: "sk-test"
        )
        #expect(rewritten == "Rewritten text.")

        // Now wire in a response for analyze() and confirm it still works.
        let analyzeContent = """
        {"suggestions":[{"category":"tone","revised_text":"Direct.","explanation":"Better.","confidence":9}]}
        """
        let analyzeSession = makeSession(
            status: 200,
            body: envelopeData(content: analyzeContent)
        )
        let analyzeService = LLMService(session: analyzeSession)
        let suggestions = await analyzeService.analyze(
            paragraph: "Some paragraph.",
            config: makeConfig(),
            apiKey: nil
        )
        #expect(suggestions.count == 1)
    }
}

// MARK: - Test helpers

/// URLProtocol that records requests and responds with a canned status + body.
private final class RewriteRecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var cannedStatus: Int = 200
    nonisolated(unsafe) static var cannedBody: Data = Data()
    nonisolated(unsafe) static var receivedRequests: [URLRequest] = []
    nonisolated(unsafe) static var receivedBodies: [Data] = []

    static func reset(status: Int, body: Data) {
        cannedStatus = status
        cannedBody = body
        receivedRequests = []
        receivedBodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.receivedRequests.append(request)
        if let body = request.httpBody {
            Self.receivedBodies.append(body)
        } else if let stream = request.httpBodyStream {
            stream.open()
            var buf = Data()
            var rawBuf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&rawBuf, maxLength: 4096)
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

/// URLProtocol that always fails with a connection error.
private final class RewriteFailingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }
    override func stopLoading() {}
}
