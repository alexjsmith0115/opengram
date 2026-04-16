import Foundation

/// DI-friendly reader for Phase 16's feature flag plus Phase 17 live-read tunables.
/// Scheduler holds this and re-reads per-call so a settings flip takes effect on the next check
/// without app relaunch. D-14.
///
/// Phase 17 extends this protocol with three live-read tunables per D-01/D-02/D-05:
/// `minIssueCount`, `minWordCount`, `idleDebounceSeconds`. Each is read per-access so UI
/// changes in the Advanced Settings tab propagate on the next qualifying check.
protocol IncrementalConfig: Sendable {
    var isIncrementalCheckingEnabled: Bool { get }
    /// Consumed in Phase 18 by the rephrase card display heuristic. Phase 17 ships the
    /// plumbing and tab UI only (CONTEXT.md D-04).
    var minIssueCount: Int { get }
    /// Consumed in Phase 18 by the rephrase card display heuristic. Phase 17 ships the
    /// plumbing and tab UI only (CONTEXT.md D-04).
    var minWordCount: Int { get }
    var idleDebounceSeconds: TimeInterval { get }
}

/// UserDefaults-backed default. Reads each key on every access (live-read, D-14).
/// Default when unset: `false` for the flag; 2 / 12 / 1.5 for the tunables (D-02, ROADMAP success criterion 4).
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
    static let isIncrementalCheckingEnabledKey = "llmIncrementalCheckingEnabled"
    static let minIssueCountKey = "llmMinIssueCount"
    static let minWordCountKey = "llmMinWordCount"
    static let idleDebounceSecondsKey = "llmIdleDebounceSeconds"

    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isIncrementalCheckingEnabled: Bool {
        defaults.bool(forKey: Self.isIncrementalCheckingEnabledKey)
    }

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
