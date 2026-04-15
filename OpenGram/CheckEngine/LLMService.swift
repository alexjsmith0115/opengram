import Foundation
import os.log

/// Concrete LLM provider that calls an OpenAI-compatible /v1/chat/completions endpoint.
/// Swift actor for concurrency safety (mirrors HarperService pattern, per D-15).
actor LLMService: LLMProviderProtocol {

    private let session: URLSession
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.opengram",
        category: "LLMService"
    )

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - LLMProviderProtocol

    func check(text: String, type: LLMCheckType, harperSpans: [String],
               config: LLMConfig, apiKey: String?) async -> [Suggestion] {
        guard config.isEnabled else { return [] }
        guard let url = config.chatCompletionsURL else {
            Self.logger.debug("Invalid chat completions URL from baseURL: \(config.baseURL)")
            return []
        }

        let systemPrompt = LLMPrompts.systemPrompt(for: type, harperSpans: harperSpans)
        let payload = ChatRequest(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: text)
            ],
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let key = apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 15 // D-10
            request.httpBody = try JSONEncoder().encode(payload)

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                Self.logger.debug("LLM HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return [] // D-08: silent failure
            }

            return parseLLMResponse(data: data, sourceText: text, checkType: type)
        } catch {
            Self.logger.debug("LLM request failed: \(error.localizedDescription)")
            return [] // D-08: silent failure
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

    // MARK: - Response Parsing (D-17: resilient JSON parsing)

    private func parseLLMResponse(data: Data, sourceText: String, checkType: LLMCheckType) -> [Suggestion] {
        guard let rawString = String(data: data, encoding: .utf8) else { return [] }

        guard let content = extractContent(from: rawString) else {
            Self.logger.debug("Could not extract content from LLM response")
            return []
        }

        let dtos = parseJSONContent(content)
        return dtos.compactMap { dto in
            mapDTOToSuggestion(dto, sourceText: sourceText, checkType: checkType)
        }
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
    /// 2. Strip preamble before first [
    /// 3. Attempt JSONDecoder on cleaned string
    /// 4. Fallback: extract individual {...} objects via brace-matching
    func parseJSONContent(_ raw: String) -> [LLMSuggestionDTO] {
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

        // Step 2: strip preamble before first [
        guard let bracketRange = cleaned.range(of: "[") else {
            return extractIndividualObjects(from: cleaned)
        }
        cleaned = String(cleaned[bracketRange.lowerBound...])

        // Step 3: JSONDecoder attempt
        if let data = cleaned.data(using: .utf8),
           let dtos = try? JSONDecoder().decode([LLMSuggestionDTO].self, from: data) {
            return dtos
        }

        // Step 4: brace-matching fallback
        return extractIndividualObjects(from: cleaned)
    }

    /// Extracts individual JSON objects by matching braces and decoding each independently.
    private func extractIndividualObjects(from text: String) -> [LLMSuggestionDTO] {
        var results: [LLMSuggestionDTO] = []
        var depth = 0
        var objectStart: String.Index?

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
                       let dto = try? JSONDecoder().decode(LLMSuggestionDTO.self, from: data) {
                        results.append(dto)
                    }
                    objectStart = nil
                }
            }
        }
        return results
    }

    // MARK: - DTO to Suggestion Mapping (D-16: substring search for offset resolution)

    private func mapDTOToSuggestion(_ dto: LLMSuggestionDTO, sourceText: String,
                                     checkType: LLMCheckType) -> Suggestion? {
        // D-16: Never trust LLM offsets. Find the original substring in source text.
        guard let range = sourceText.range(of: dto.original) else {
            Self.logger.debug("LLM original text not found in source: \(dto.original.prefix(50))")
            return nil
        }

        return Suggestion(
            id: UUID(),
            range: range,
            original: dto.original,
            primaryReplacement: dto.replacement,
            allReplacements: [dto.replacement],
            message: dto.reason,
            category: checkType.checkCategory,
            source: .llm,
            priority: 50 // LLM suggestions are lower priority than Harper (which uses raw.priority from harper-core)
        )
    }

    // MARK: - Request Types

    private struct ChatRequest: Encodable, Sendable {
        let messages: [ChatMessage]
        let temperature: Double
        let maxTokens: Int

        enum CodingKeys: String, CodingKey {
            case messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct ChatMessage: Encodable, Sendable {
        let role: String
        let content: String
    }
}
