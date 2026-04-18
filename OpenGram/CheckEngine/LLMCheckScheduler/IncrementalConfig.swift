import Foundation

/// DI-friendly reader for live-read tunables used by the incremental LLM check path.
/// Scheduler holds this and re-reads per-call so a settings change takes effect on the next
/// check without app relaunch.
///
/// Tunables:
/// - `minIssueCount`, `minWordCount`: consumed by the rephrase card display heuristic
/// - `idleDebounceSeconds`: consumed by the keystroke-idle scheduling path
protocol IncrementalConfig: Sendable {
    var minIssueCount: Int { get }
    var minWordCount: Int { get }
    var idleDebounceSeconds: TimeInterval { get }
}

/// UserDefaults-backed default. Reads each key on every access (live-read).
/// Default when unset: 2 / 12 / 1.5 for the tunables (ROADMAP success criterion 4).
///
/// `@unchecked Sendable` because `UserDefaults` is thread-safe by design but not formally
/// declared Sendable in the Foundation SDK. Matches the pattern used elsewhere in the codebase
/// for DI-injected UserDefaults readers under Swift 6 strict concurrency.
struct UserDefaultsIncrementalConfig: IncrementalConfig, @unchecked Sendable {
    static let defaultMinIssueCount: Int = 2
    static let defaultMinWordCount: Int = 12
    static let defaultIdleDebounceSeconds: TimeInterval = 1.5

    // Single source of truth for the UserDefaults key strings. `AdvancedSettingsView`
    // re-declares the same literals in its `@AppStorage` wrappers (property-wrapper
    // arguments require compile-time string literals) and asserts equality via
    // `appStorageKeys_matchConfigKeys` test to prevent drift.
    static let minIssueCountKey = "llmMinIssueCount"
    static let minWordCountKey = "llmMinWordCount"
    static let idleDebounceSecondsKey = "llmIdleDebounceSeconds"

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// `defaults.object(forKey:)` (not `defaults.integer(forKey:)`) to distinguish unset from
    /// a user-set zero — `integer(forKey:)` returns 0 for missing keys, collapsing both cases.
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
