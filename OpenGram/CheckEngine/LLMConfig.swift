import Foundation

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

    static let `default` = LLMConfig(
        baseURL: "http://localhost:1234/v1",
        model: "default",
        enabledChecks: Set(LLMCheckType.allCases),
        temperature: 0.3,
        maxTokens: 1024,
        requestTimeout: 60
    )

    /// True if at least one check type is enabled and the base URL is non-empty.
    var isEnabled: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !enabledChecks.isEmpty
    }

    /// Builds the full chat completions URL from baseURL.
    /// Returns nil if the URL is malformed.
    var chatCompletionsURL: URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(base)/chat/completions")
    }
}
