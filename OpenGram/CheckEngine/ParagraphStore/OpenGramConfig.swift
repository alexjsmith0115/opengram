import Foundation

/// UserDefaults-backed tunables, live-read on every property access so a
/// Settings UI write is visible on the next reconcile tick without restart.
///
/// Callers who prefer event-driven hot reload observe `OpenGramConfig.didChangeNotification`
/// on `NotificationCenter.default` — `Settings` writers post it after `defaults.set(...)`.
///
/// `@unchecked Sendable` — `UserDefaults` is thread-safe by Foundation contract but not
/// formally declared `Sendable` in the SDK.
struct OpenGramConfig: @unchecked Sendable {
    // MARK: - Paragraph store keys

    static let harperDebounceMsKey           = "harperDebounceMs"
    static let llmDebounceMsKey              = "llmDebounceMs"
    static let llmRequestTimeoutSecondsKey   = "llmRequestTimeoutSeconds"
    static let minParagraphLengthKey         = "minParagraphLength"
    static let minParagraphWordCountKey      = "minParagraphWordCount"

    // MARK: - Display-heuristic tunables (AdvancedSettingsView @AppStorage literals
    //        must match these keys verbatim — property wrappers require compile-time
    //        string literals, so the pair is drift-guarded by AdvancedSettingsViewTests)

    static let minIssueCountKey              = "llmMinIssueCount"
    static let minWordCountKey               = "llmMinWordCount"
    static let idleDebounceSecondsKey        = "llmIdleDebounceSeconds"

    // MARK: - Defaults

    static let defaultHarperDebounceMs          = 300
    static let defaultLLMDebounceMs             = 2000
    static let defaultLLMRequestTimeoutSeconds  = 30
    static let defaultMinParagraphLength        = 30
    static let defaultMinParagraphWordCount     = 2
    static let defaultMinIssueCount             = 2
    static let defaultMinWordCount              = 12
    static let defaultIdleDebounceSeconds       = 1.5

    static let didChangeNotification = Notification.Name("OpenGramConfigDidChange")

    // MARK: - Storage

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    // MARK: - Paragraph store tunables

    var harperDebounceMs: Int {
        defaults.object(forKey: Self.harperDebounceMsKey) as? Int ?? Self.defaultHarperDebounceMs
    }

    var llmDebounceMs: Int {
        defaults.object(forKey: Self.llmDebounceMsKey) as? Int ?? Self.defaultLLMDebounceMs
    }

    var llmRequestTimeoutSeconds: Int {
        defaults.object(forKey: Self.llmRequestTimeoutSecondsKey) as? Int ?? Self.defaultLLMRequestTimeoutSeconds
    }

    var minParagraphLength: Int {
        defaults.object(forKey: Self.minParagraphLengthKey) as? Int ?? Self.defaultMinParagraphLength
    }

    var minParagraphWordCount: Int {
        defaults.object(forKey: Self.minParagraphWordCountKey) as? Int ?? Self.defaultMinParagraphWordCount
    }

    // MARK: - Absorbed legacy tunables (DisplayHeuristic consumers)

    var minIssueCount: Int {
        defaults.object(forKey: Self.minIssueCountKey) as? Int ?? Self.defaultMinIssueCount
    }

    var minWordCount: Int {
        defaults.object(forKey: Self.minWordCountKey) as? Int ?? Self.defaultMinWordCount
    }

    var idleDebounceSeconds: TimeInterval {
        defaults.object(forKey: Self.idleDebounceSecondsKey) as? Double ?? Self.defaultIdleDebounceSeconds
    }
}

/// Helper Settings UI can call after mutating UserDefaults — broadcasts change so
/// eager-rescheduling consumers can flush caches.
extension OpenGramConfig {
    static func postDidChange(to center: NotificationCenter = .default) {
        center.post(name: Self.didChangeNotification, object: nil)
    }
}
