import Foundation

/// Per-category check type used to let users enable/disable individual LLM check dimensions
/// (tone, clarity, rephrase) from Settings. Filtered in LLMConfig.isEnabled and passed to
/// LLMService so only the configured dimensions are requested.
enum LLMCheckType: String, Sendable, CaseIterable, Codable {
    case tone
    case clarity
    case rephrase
}

/// Non-secret LLM configuration. Stored in UserDefaults via @AppStorage on the UI side.
/// Passed as a value type to LLMService methods so the actor never reads @AppStorage directly
/// (Pitfall 2: @AppStorage is @MainActor-isolated).
struct LLMConfig: Codable, Sendable, Equatable {
    var baseURL: String
    var model: String
    var enabledChecks: Set<LLMCheckType>
    var temperature: Double
    var maxTokens: Int
    var requestTimeout: TimeInterval
    var confidenceThreshold: Int

    static let defaultConfidenceThreshold = 7

    static let `default` = LLMConfig(
        baseURL: "http://localhost:1234/v1",
        model: "default",
        enabledChecks: Set(LLMCheckType.allCases),
        temperature: 0.3,
        maxTokens: 1024,
        requestTimeout: 60,
        confidenceThreshold: defaultConfidenceThreshold
    )

    /// True if at least one check type is enabled and the base URL is non-empty.
    var isEnabled: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !enabledChecks.isEmpty
    }

    /// Builds the full chat completions URL from baseURL using URLComponents.
    /// Returns nil if the URL is malformed.
    var chatCompletionsURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed) else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/chat/completions"
        return components.url
    }
}
