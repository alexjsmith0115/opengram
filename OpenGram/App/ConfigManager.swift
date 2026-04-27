import Foundation
import Security

/// Reads LLM configuration from UserDefaults and API key from Keychain.
/// Static methods — no instance state. Extracted from AppDelegate to avoid duplication.
enum ConfigManager {

    static func currentLLMConfig() -> LLMConfig {
        let defaults = UserDefaults.standard
        return LLMConfig(
            baseURL: defaults.string(forKey: "llmBaseURL") ?? LLMConfig.default.baseURL,
            model: defaults.string(forKey: "llmModel") ?? LLMConfig.default.model,
            enabledChecks: {
                var checks = Set<LLMCheckType>()
                if defaults.object(forKey: "llmEnableTone") == nil || defaults.bool(forKey: "llmEnableTone") { checks.insert(.tone) }
                if defaults.object(forKey: "llmEnableRephrase") == nil || defaults.bool(forKey: "llmEnableRephrase") { checks.insert(.rephrase) }
                return checks
            }(),
            temperature: defaults.object(forKey: "llmTemperature") != nil
                ? defaults.double(forKey: "llmTemperature")
                : LLMConfig.default.temperature,
            maxTokens: LLMConfig.default.maxTokens,
            requestTimeout: defaults.object(forKey: "llmRequestTimeout") != nil
                ? defaults.double(forKey: "llmRequestTimeout")
                : LLMConfig.default.requestTimeout,
            confidenceThreshold: LLMConfig.defaultConfidenceThreshold
        )
    }

    static func currentAPIKey() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.opengram.llm",
            kSecAttrAccount: "apiKey",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }
}

extension ConfigManager: RewriteConfigProvider {
    var llmConfig: LLMConfig { ConfigManager.currentLLMConfig() }
    func currentAPIKey() -> String? { ConfigManager.currentAPIKey() }
}

/// Concrete value-type passed into objects that need `RewriteConfigProvider`.
/// Delegates to the static `ConfigManager` accessors.
struct LiveConfigProvider: RewriteConfigProvider, Sendable {
    var llmConfig: LLMConfig { ConfigManager.currentLLMConfig() }
    func currentAPIKey() -> String? { ConfigManager.currentAPIKey() }
}
