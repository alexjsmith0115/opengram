import Foundation
import os.log

/// Concrete LLM provider that calls an OpenAI-compatible /v1/chat/completions endpoint.
/// Swift actor for concurrency safety (mirrors HarperService pattern, per D-15).
/// Sends a single consolidated request for all three style dimensions (clarity, tone, rephrase).
actor LLMService: LLMProviderProtocol {

    private let session: URLSession
    private var currentTask: Task<[LLMStyleSuggestion], Error>?
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "LLMService"
    )

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - LLMProviderProtocol

    func analyze(paragraph: String, config: LLMConfig, apiKey: String?, harperSpans: [String] = []) async -> [LLMStyleSuggestion] {
        // Cancel any in-flight request before starting a new one.
        currentTask?.cancel()

        Self.logger.info("analyze() called — baseURL=\(config.baseURL) model=\(config.model) paragraph=\(paragraph.prefix(80))...")

        let session = self.session
        let task = Task<[LLMStyleSuggestion], Error> {
            guard config.isEnabled else {
                Self.logger.info("LLM disabled (isEnabled=false) — skipping")
                return []
            }
            guard let url = config.chatCompletionsURL else {
                Self.logger.error("Invalid chat completions URL from baseURL: \(config.baseURL)")
                return []
            }
            Self.logger.info("POST → \(url.absoluteString)")

            let payload = ChatRequest(
                model: config.model,
                messages: [
                    ChatMessage(role: "system", content: LLMPrompts.systemPrompt(harperSpans: harperSpans, confidenceThreshold: config.confidenceThreshold)),
                    ChatMessage(role: "user", content: LLMPrompts.userMessage(for: paragraph))
                ],
                temperature: config.temperature,
                maxTokens: config.maxTokens
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = config.requestTimeout
            request.httpBody = try JSONEncoder().encode(payload)

            try Task.checkCancellation()

            let (data, response) = try await session.data(for: request)

            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.error("LLM HTTP error: status=\(code)")
                if let body = String(data: data, encoding: .utf8) {
                    Self.logger.error("Response body: \(body.prefix(500))")
                }
                return []
            }

            Self.logger.info("LLM HTTP \(httpResponse.statusCode) — \(data.count) bytes")
            if let raw = String(data: data, encoding: .utf8) {
                Self.logger.info("Raw response: \(raw.prefix(500))")
            }

            let results = try parseResponse(data: data, paragraph: paragraph, confidenceThreshold: config.confidenceThreshold)
            Self.logger.info("Parsed \(results.count) suggestions")
            for (i, s) in results.enumerated() {
                Self.logger.info("  [\(i)] \(s.category.rawValue) conf=\(s.confidence): \(s.explanation.prefix(60))")
            }
            return results
        }

        currentTask = task

        defer {
            // WR-03: clear the slot once done so the last request's closure (paragraph text,
            // API key) doesn't linger on the actor until the next analyze() call.
            if currentTask == task { currentTask = nil }
        }

        do {
            return try await task.value
        } catch is CancellationError {
            Self.logger.info("LLM request cancelled")
            return []
        } catch {
            Self.logger.error("LLM request failed: \(error.localizedDescription)")
            return [] // D-08: silent failure
        }
    }

    /// Context-aware analyze for incremental scheduler (D-05/D-06).
    /// Cancellation is per-call (caller owns the Task) — does NOT touch currentTask,
    /// so the legacy analyze(paragraph:) single-flight path is unaffected.
    func analyze(
        target: String,
        previousContext: String?,
        nextContext: String?,
        config: LLMConfig,
        apiKey: String?,
        harperSpans: [String] = []
    ) async -> [LLMStyleSuggestion] {
        guard config.isEnabled else {
            Self.logger.info("LLM disabled (isEnabled=false) — skipping target analyze")
            return []
        }
        guard let url = config.chatCompletionsURL else {
            Self.logger.error("Invalid chat completions URL from baseURL: \(config.baseURL)")
            return []
        }

        let session = self.session
        do {
            let payload = ChatRequest(
                model: config.model,
                messages: [
                    ChatMessage(role: "system", content: LLMPrompts.systemPrompt(harperSpans: harperSpans, confidenceThreshold: config.confidenceThreshold)),
                    ChatMessage(role: "user", content: LLMPrompts.userMessageIncremental(target: target, previousContext: previousContext, nextContext: nextContext))
                ],
                temperature: config.temperature,
                maxTokens: config.maxTokens
            )

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = config.requestTimeout
            request.httpBody = try JSONEncoder().encode(payload)

            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                Self.logger.error("LLM HTTP error (target): status=\(code)")
                return []
            }

            return (try? parseResponse(data: data, paragraph: target, confidenceThreshold: config.confidenceThreshold)) ?? []
        } catch is CancellationError {
            Self.logger.info("LLM target request cancelled")
            return []
        } catch {
            Self.logger.error("LLM target request failed: \(error.localizedDescription)")
            return []
        }
    }

    func healthCheck(config: LLMConfig, apiKey: String?) async -> Bool {
        guard let baseURL = URL(string: config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { return false }
        let modelsURL = baseURL.appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            Self.logger.debug("LLM health check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Response Parsing

    /// Extracts the assistant message content and decodes via LLMResponseDTO.
    /// Throws on unrecoverable parse failure — caller maps to empty array.
    private func parseResponse(data: Data, paragraph: String, confidenceThreshold: Int = LLMConfig.defaultConfidenceThreshold) throws -> [LLMStyleSuggestion] {
        guard let rawString = String(data: data, encoding: .utf8) else {
            return []
        }

        guard let content = extractContent(from: rawString) else {
            Self.logger.debug("Could not extract content from LLM response")
            return []
        }

        return parseJSONContent(content, paragraph: paragraph, confidenceThreshold: confidenceThreshold)
    }

    /// Extracts the assistant message content from the OpenAI chat completion JSON envelope.
    private func extractContent(from raw: String) -> String? {
        struct ChatCompletion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let data = raw.data(using: .utf8),
              let completion = try? JSONDecoder().decode(ChatCompletion.self, from: data),
              let content = completion.choices.first?.message.content else {
            return nil
        }
        return content
    }

    /// Four-step resilient JSON parser (D-17):
    /// 1. Strip markdown code fences
    /// 2. Strip preamble before first {
    /// 3. Attempt JSONDecoder via LLMResponseDTO
    /// 4. Fallback: extract individual suggestion objects via brace-matching
    func parseJSONContent(_ raw: String, paragraph: String, confidenceThreshold: Int = LLMConfig.defaultConfidenceThreshold) -> [LLMStyleSuggestion] {
        var cleaned = raw

        // Step 1: strip markdown fences
        if let fenceStart = cleaned.range(of: "```json") {
            cleaned = String(cleaned[fenceStart.upperBound...])
            if let fenceEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
        } else if let fenceStart = cleaned.range(of: "```") {
            cleaned = String(cleaned[fenceStart.upperBound...])
            if let fenceEnd = cleaned.range(of: "```") {
                cleaned = String(cleaned[..<fenceEnd.lowerBound])
            }
        }

        // Step 2: strip preamble before first {
        guard let braceRange = cleaned.range(of: "{") else {
            return []
        }
        cleaned = String(cleaned[braceRange.lowerBound...])

        // Step 3: attempt direct decode via LLMResponseDTO
        if let data = cleaned.data(using: .utf8),
           let suggestions = try? LLMResponseDTO.toModels(from: data, originalText: paragraph, confidenceThreshold: confidenceThreshold) {
            return suggestions
        }

        // Step 4: brace-matching fallback — try to salvage a partial response
        return extractSuggestionsViaBraceMatching(from: cleaned, paragraph: paragraph, confidenceThreshold: confidenceThreshold)
    }

    /// Extracts individual suggestion objects by matching braces, wraps them in the
    /// expected envelope, and decodes each independently.
    private func extractSuggestionsViaBraceMatching(from text: String, paragraph: String, confidenceThreshold: Int = LLMConfig.defaultConfidenceThreshold) -> [LLMStyleSuggestion] {
        // Look for a "suggestions" array and try to extract its objects
        var results: [LLMStyleSuggestion] = []
        var depth = 0
        var objectStart: String.Index?
        var inSuggestionsArray = false

        // Simple heuristic: find "suggestions" key to know we're in the right structure
        if text.contains("\"suggestions\"") {
            inSuggestionsArray = true
        }

        guard inSuggestionsArray else { return [] }

        for i in text.indices {
            let ch = text[i]
            if ch == "{" {
                if depth == 0 { objectStart = i }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let start = objectStart {
                    let objectString = String(text[start...i])
                    if let data = objectString.data(using: .utf8),
                       let dto = try? JSONDecoder().decode(LLMResponseDTO.SuggestionDTO.self, from: data),
                       let suggestion = dto.toModel(originalText: paragraph, confidenceThreshold: confidenceThreshold) {
                        results.append(suggestion)
                    }
                    objectStart = nil
                }
            }
        }
        return results
    }

    // MARK: - Rewrite

    /// Stateless rewrite call. Does NOT touch `currentTask` or any single-flight state.
    /// Caller owns the Task lifecycle; concurrent analyze() calls are unaffected.
    /// Returns the raw model output so meaningful whitespace and paragraph breaks are preserved.
    /// Throws `LLMRewriteError.emptyResponse` when the trimmed content is blank.
    func rewrite(
        text: String,
        tone: RewriteTone,
        config: LLMConfig,
        apiKey: String?
    ) async throws -> String {
        guard let url = config.chatCompletionsURL else {
            throw LLMRewriteError.transport(URLError(.badURL))
        }

        let payload = ChatRequest(
            model: config.model,
            messages: [
                ChatMessage(role: "system", content: LLMPrompts.rewriteSystemPrompt(tone: tone)),
                ChatMessage(role: "user", content: LLMPrompts.rewriteUserMessage(text: text))
            ],
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = config.requestTimeout
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw LLMRewriteError.transport(error)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMRewriteError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LLMRewriteError.transport(URLError(.badServerResponse))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMRewriteError.http(status: http.statusCode)
        }

        struct RewriteCompletion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }

        guard let completion = try? JSONDecoder().decode(RewriteCompletion.self, from: data),
              let content = completion.choices.first?.message.content else {
            throw LLMRewriteError.decodingFailure
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMRewriteError.emptyResponse
        }

        return content
    }

    // MARK: - Request Types

    private struct ChatRequest: Encodable, Sendable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct ChatMessage: Encodable, Sendable {
        let role: String
        let content: String
    }
}

// MARK: -

public enum LLMRewriteError: Error, Sendable {
    case emptyResponse
    case decodingFailure
    case http(status: Int)
    case transport(Error)
}
